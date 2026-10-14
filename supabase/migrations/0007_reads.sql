-- Screen reads: the Play feed, My Hits, and the badge count. One round trip each.

create or replace function public.badge_count(p_user uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from public.join_requests r join public.hits h on h.id = r.hit_id
     where h.host_id = p_user and r.status = 'pending' and h.status in ('open', 'confirmed') and h.starts_at > now())
    + (select count(*) from public.hit_invites i join public.hits h on h.id = i.hit_id
       where i.target_user_id = p_user and i.status = 'open' and i.expires_at > now() and h.status in ('open', 'confirmed') and h.starts_at > now())
    + (select count(*) from public.chat_members cm
       where cm.user_id = p_user and cm.left_at is null and exists (
         select 1 from public.messages m where m.chat_id = cm.chat_id and m.sender_id is distinct from p_user
           and m.created_at > coalesce(cm.last_read_at, '-infinity'::timestamptz)
           and (m.sender_id is null or not public.is_blocked_either(p_user, m.sender_id))))
  )::integer;
$$;

-- Which block of the week a time falls in (bit index in the availability mask), or null outside the blocks.
create or replace function public.availability_bit(p_at timestamptz) returns integer
language sql immutable as $$
  select case
    when extract(hour from local) between 7 and 10 then (extract(isodow from local)::int - 1) * 3
    when extract(hour from local) between 12 and 15 then (extract(isodow from local)::int - 1) * 3 + 1
    when extract(hour from local) between 17 and 20 then (extract(isodow from local)::int - 1) * 3 + 2
    end
  from (select p_at at time zone 'America/New_York' as local) t;
$$;

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
        order by h.starts_at limit 20
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
          and me.home_point is not null and extensions.st_dwithin(c.point, me.home_point, me.radius_mi * 1609.344)
        order by rn limit 30
      ) h
    ), '[]'::jsonb),

    'free_this_week', coalesce((
      select jsonb_agg(public.player_card(f.other))
      from (
        select case when fr.user_a = v_user then fr.user_b else fr.user_a end as other
        from public.friendships fr where fr.status = 'accepted' and v_user in (fr.user_a, fr.user_b)
      ) f
      join public.profiles p on p.id = f.other
      where public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
        and (p.availability_mask & ~coalesce(p.busy_mask_week, 0) & public.remaining_week_mask()) <> 0
      limit 6
    ), '[]'::jsonb),

    'my_upcoming_count', (
      select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
      where hp.user_id = v_user and hp.left_at is null and h.status in ('open', 'confirmed') and h.starts_at > v_now
    ),
    'badge', public.badge_count(v_user)
  );
end $$;

-- A hit the viewer could join: live, future, open spots, not theirs, visible to them.
create or replace function public.feed_candidate(p_hit uuid, p_viewer uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h join public.profiles hp on hp.id = h.host_id
    where h.id = p_hit and h.status in ('open', 'confirmed') and h.spots_open > 0 and h.starts_at > now()
      and h.host_id <> p_viewer and h.visibility <> 'invite_only'
      and hp.suspended_at is null and hp.deleted_at is null and hp.onboarding_completed_at is not null
      and not public.is_blocked_either(p_viewer, h.host_id)
      and not exists (select 1 from public.hit_players p where p.hit_id = h.id and p.user_id = p_viewer and p.left_at is null)
      and not exists (select 1 from public.join_requests r where r.hit_id = h.id and r.user_id = p_viewer and r.status = 'pending')
      and ((h.visibility = 'anyone' and hp.hit_visibility = 'anyone') or (h.visibility in ('anyone', 'friends') and public.is_friend(p_viewer, h.host_id)))
  );
$$;

-- Bits for the blocks still ahead this week (now through Sunday evening).
create or replace function public.remaining_week_mask() returns integer
language sql stable as $$
  -- Between two blocks the next one today still counts; after the evening, tomorrow's morning is first.
  select coalesce(bit_or(1 << (d * 3 + b)), 0)::integer
  from generate_series(0, 6) d, generate_series(0, 2) b, (select now() at time zone 'America/New_York' as local) t
  where (d * 3 + b) >= (extract(isodow from local)::int - 1) * 3 + case
    when extract(hour from local) < 11 then 0
    when extract(hour from local) < 16 then 1
    when extract(hour from local) < 21 then 2
    else 3 end;
$$;

-- The small caption under a feed row: home court, friend of a friend, fits your availability, closest.
create or replace function public.feed_reason(p_hit uuid, p_viewer uuid, p_is_closest boolean) returns text
language plpgsql stable security definer set search_path = public as $$
declare h public.hits; me public.profiles; v_bit integer; v_mutual text;
begin
  select * into h from public.hits where id = p_hit;
  select * into me from public.profiles where id = p_viewer;
  if (select count(*) from public.hits x join public.hit_players xp on xp.hit_id = x.id
      where x.court_id = h.court_id and xp.user_id = p_viewer and x.status = 'played') >= 2 then
    return 'Your home court';
  end if;
  v_bit := public.availability_bit(h.starts_at);
  if v_bit is not null and (me.availability_mask & (1 << v_bit)) <> 0 then
    return 'Fits your ' || to_char(h.starts_at at time zone 'America/New_York', 'FMDay');
  end if;
  select p.first_name into v_mutual from public.profiles p
  where p.id <> p_viewer and p.id <> h.host_id and public.is_friend(p_viewer, p.id) and public.is_friend(h.host_id, p.id) limit 1;
  if v_mutual is not null then return 'Friend of ' || v_mutual; end if;
  if p_is_closest then return 'Closest court to you'; end if;
  return null;
end $$;

-- Upcoming commitments and past hits, with the state each row shows.
create or replace function public.get_my_hits() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); v_now timestamptz := now();
begin
  return jsonb_build_object(
    'upcoming', coalesce((
      select jsonb_agg(item order by starts_at) from (
        select public.hit_json(h.id, v_user) || jsonb_build_object('state',
          case when h.host_id = v_user and h.status = 'open' and exists (select 1 from public.join_requests r where r.hit_id = h.id and r.status = 'pending') then 'open_requests'
               when h.host_id = v_user and h.status = 'open' then 'open_waiting'
               else 'confirmed' end) as item, h.starts_at
        from public.hits h join public.hit_players hp on hp.hit_id = h.id
        where hp.user_id = v_user and hp.left_at is null and h.status in ('open', 'confirmed')
          and h.starts_at + (h.duration_min || ' minutes')::interval > v_now
        union all
        select public.hit_json(h.id, v_user) || jsonb_build_object('state', 'pending', 'request_id', r.id), h.starts_at
        from public.join_requests r join public.hits h on h.id = r.hit_id
        where r.user_id = v_user and r.status = 'pending' and h.status in ('open', 'confirmed') and h.starts_at > v_now
        union all
        select public.hit_json(h.id, v_user) || jsonb_build_object('state', 'invited', 'invite_id', i.id), h.starts_at
        from public.hit_invites i join public.hits h on h.id = i.hit_id
        where i.target_user_id = v_user and i.status = 'open' and i.expires_at > v_now and h.status in ('open', 'confirmed') and h.starts_at > v_now
      ) x
    ), '[]'::jsonb),
    'past', coalesce((
      select jsonb_agg(item order by starts_at desc) from (
        select public.hit_json(h.id, v_user) || jsonb_build_object('state', h.status::text) as item,
          h.starts_at
        from public.hits h join public.hit_players hp on hp.hit_id = h.id
        where hp.user_id = v_user and hp.left_at is null and (h.status in ('played', 'cancelled', 'expired') or h.starts_at + (h.duration_min || ' minutes')::interval <= v_now)
        order by h.starts_at desc limit 50
      ) x
    ), '[]'::jsonb)
  );
end $$;
