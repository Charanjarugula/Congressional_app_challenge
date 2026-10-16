-- Distance is an optional feed filter, not a profile-level visibility rule.
-- Keep friendship, blocking, age, visibility and busy-time checks unchanged.
create or replace function public.get_play_feed() returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_onboarded(); me public.profiles; v_now timestamptz := now();
begin
  select * into me from public.profiles where id = v_user;

  return jsonb_build_object(
    'needs_reply', coalesce((
      select jsonb_agg(item order by ts desc) from (
        select jsonb_build_object('kind', 'join_request', 'request_id', r.id, 'player', public.player_card(r.user_id),
                                  'hit', public.hit_json(h.id, v_user), 'created_at', r.created_at) as item, r.created_at as ts
        from public.join_requests r join public.hits h on h.id = r.hit_id
        where h.host_id = v_user and r.status = 'pending' and h.status in ('open', 'confirmed') and h.starts_at > v_now
        union all
        select jsonb_build_object('kind', 'invite', 'invite_id', i.id, 'host', public.player_card(h.host_id),
                                  'hit', public.hit_json(h.id, v_user), 'created_at', i.created_at), i.created_at
        from public.hit_invites i join public.hits h on h.id = i.hit_id
        where i.target_user_id = v_user and i.status = 'open' and i.expires_at > v_now and h.status in ('open', 'confirmed')
          and h.starts_at > v_now and h.spots_open > 0
          and not public.is_hit_member(h.id, v_user)
        union all
        select jsonb_build_object('kind', 'accepted', 'request_id', r.id, 'host', public.player_card(h.host_id),
                                  'hit', public.hit_json(h.id, v_user), 'created_at', r.responded_at), r.responded_at
        from public.join_requests r join public.hits h on h.id = r.hit_id
        where r.user_id = v_user and r.status = 'accepted' and r.seen_by_requester_at is null and h.status = 'confirmed' and h.starts_at > v_now
      ) x
    ), '[]'::jsonb),

    'from_friends', coalesce((
      select jsonb_agg(public.hit_json(h.id, v_user) || jsonb_build_object('reason', public.feed_reason(h.id, v_user, false)) order by h.starts_at)
      from (
        select h.* from public.hits h
        join public.profiles hp on hp.id = h.host_id
        where h.status in ('open', 'confirmed') and h.starts_at > now() and h.spots_open > 0
          and public.feed_candidate(h.id, v_user) and public.is_friend(v_user, h.host_id)
          and not public.busy_at(v_user, h.starts_at)
        order by h.starts_at
      ) h
    ), '[]'::jsonb),

    'near_you', coalesce((
      select jsonb_agg(public.hit_json(h.id, v_user) || jsonb_build_object('reason', public.feed_reason(h.id, v_user, h.rn = 1)) order by h.rn)
      from (
        select h.*, row_number() over (order by extensions.st_distance(c.point, me.home_point), h.starts_at) as rn
        from public.hits h
        join public.courts c on c.id = h.court_id
        where h.status in ('open', 'confirmed') and h.starts_at > now() and h.spots_open > 0
          and public.feed_candidate(h.id, v_user) and not public.is_friend(v_user, h.host_id)
          and not public.busy_at(v_user, h.starts_at)
        order by rn
      ) h
    ), '[]'::jsonb),

    'free_this_week', coalesce((
      select jsonb_agg(public.player_card(free.other))
      from (
        select f.other
        from (
          select case when fr.user_a = v_user then fr.user_b else fr.user_a end as other
          from public.friendships fr where fr.status = 'accepted' and v_user in (fr.user_a, fr.user_b)
        ) f
        join public.profiles p on p.id = f.other
        where public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
          and (p.availability_mask & ~coalesce(p.busy_mask_week, 0) & ~p.busy_mask & public.remaining_week_mask(p.time_zone)) <> 0
        order by p.first_name
        limit 6   -- six cards at most; the cut has to happen before the aggregate
      ) free
    ), '[]'::jsonb),

    'my_upcoming_count', (
      select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
      where hp.user_id = v_user and hp.left_at is null and h.status in ('open', 'confirmed') and h.starts_at > v_now
    ),
    'badge', public.badge_count(v_user)
  );
end $$;
