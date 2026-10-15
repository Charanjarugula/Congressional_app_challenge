-- A new player's first look at the app: players near them, and how much is going on nearby.
--
-- 1. Demo accounts (demo.*@courtly.app and the App Review account) only ever see each other.
--    Real players never get a demo player's hit in their feed or as a suggestion, so nothing on
--    screen is made up.
-- 2. Friend suggestions gain a "near you" source for players who let anyone see their hits, ranked
--    below mutual friends, groups, past hits and contacts. Hosts of an open hit nearby come first,
--    then players at the same level, then players free when you are.
-- "Near" reaches the player's own radius, at least 25 miles, so a quiet area still shows the county.
-- 3. get_area_pulse: how many players, open hits this week and courts are near the player.

create or replace function private.is_demo_account(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u
    where u.id = p_user and (u.email like 'demo.%@courtly.app' or u.email = 'reviewer@courtly.app')
  );
$$;

-- True when the viewer must not see that player: a demo account seen by a real one.
create or replace function private.hidden_demo(p_viewer uuid, p_other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select private.is_demo_account(p_other) and not private.is_demo_account(p_viewer);
$$;

create or replace function public.feed_candidate(p_hit uuid, p_viewer uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h join public.profiles hp on hp.id = h.host_id
    where h.id = p_hit and h.status in ('open', 'confirmed') and h.spots_open > 0 and h.starts_at > now()
      and h.host_id <> p_viewer and h.visibility <> 'invite_only'
      and hp.suspended_at is null and hp.deleted_at is null and hp.onboarding_completed_at is not null
      and not public.is_blocked_either(p_viewer, h.host_id)
      and not private.hidden_demo(p_viewer, h.host_id)
      and not exists (select 1 from public.hit_players p where p.hit_id = h.id and p.user_id = p_viewer and p.left_at is null)
      and not exists (select 1 from public.join_requests r where r.hit_id = h.id and r.user_id = p_viewer and r.status = 'pending')
      and ((h.visibility = 'anyone' and hp.hit_visibility = 'anyone') or (h.visibility in ('anyone', 'friends') and public.is_friend(p_viewer, h.host_id)))
  );
$$;

create or replace function public.get_friend_suggestions(p_known_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  return coalesce((
    with me as (
      select p.home_point, p.radius_mi, p.level, p.availability_mask from public.profiles p where p.id = v_user
    ),
    mine as (
      select case when f.user_a = v_user then f.user_b else f.user_a end as id
      from public.friendships f where v_user in (f.user_a, f.user_b) and f.status = 'accepted'
    ),
    candidates as (
      select fof.other, 'mutual' as source, count(*)::int as weight, 0::double precision as score,
             'Friends with ' || array_to_string((array_agg(p.first_name order by p.first_name))[1:2], ' and ') as reason
      from mine
      join public.friendships f on mine.id in (f.user_a, f.user_b) and f.status = 'accepted'
      cross join lateral (select case when f.user_a = mine.id then f.user_b else f.user_a end as other) fof
      join public.profiles p on p.id = mine.id
      where fof.other <> v_user and fof.other not in (select id from mine)
      group by fof.other
      union all
      select m2.user_id, 'group', 2, 0, 'In ' || c.name || ' with you'
      from public.chat_members m1
      join public.chats c on c.id = m1.chat_id and c.type = 'group'
      join public.chat_members m2 on m2.chat_id = c.id and m2.user_id <> v_user and m2.left_at is null
      where m1.user_id = v_user and m1.left_at is null
      union all
      select b.user_id, 'played', 3, 0, 'You hit together on ' || to_char(h.starts_at at time zone 'America/New_York', 'Mon FMDD')
      from public.hit_players a
      join public.hit_players b on b.hit_id = a.hit_id and b.user_id <> v_user
      join public.hits h on h.id = a.hit_id and h.status = 'played'
      where a.user_id = v_user
      union all
      select k, 'contacts', 1, 0, 'In your contacts' from unnest(p_known_ids) as k
      union all
      -- Near you: only players who let anyone see their hits, so nobody private is put in front of strangers.
      select p.id, 'nearby', 0,
             (case when nh.starts_at is not null then 4 else 0 end)
             + (case when p.level = me.level then 2 else 0 end)
             + (case when (p.availability_mask & me.availability_mask) <> 0 then 1 else 0 end)
             - extensions.st_distance(p.home_point, me.home_point) / 40000.0,
             case
               when nh.starts_at is not null then 'Hosting a hit ' || to_char(nh.starts_at at time zone 'America/New_York', 'FMDay')
               when p.level = me.level and (p.availability_mask & me.availability_mask) <> 0 then 'Your level, free when you are'
               when p.level = me.level then 'Your level, plays near you'
               else 'Plays near you'
             end
      from public.profiles p
      cross join me
      left join lateral (
        select h.starts_at from public.hits h
        where h.host_id = p.id and public.feed_candidate(h.id, v_user)
        order by h.starts_at limit 1
      ) nh on true
      where me.home_point is not null and p.home_point is not null
        and p.hit_visibility = 'anyone'
        and extensions.st_dwithin(p.home_point, me.home_point, greatest(coalesce(me.radius_mi, 10), 25) * 1609.344)
    ),
    ranked as (
      select distinct on (other) other, source, reason, weight, score
      from candidates
      where other <> v_user and public.is_active_user(other) and not public.is_blocked_either(v_user, other)
        and not private.hidden_demo(v_user, other)
        and public.relationship_to(v_user, other) = 'none'
      order by other, weight desc, score desc
    )
    select jsonb_agg(public.player_card(r.other) || jsonb_build_object(
      'reason', r.reason, 'source', r.source,
      'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, r.other))
    ) order by r.weight desc, r.score desc, r.reason)
    from (select * from ranked order by weight desc, score desc limit 20) r
  ), '[]'::jsonb);
end $$;

-- What is going on near the player, for the first screens a new player sees.
create or replace function public.get_area_pulse() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_user uuid := public.assert_signed_in();
  me record;
  v_reach double precision;
begin
  select p.home_point, p.radius_mi, p.area_label into me from public.profiles p where p.id = v_user;
  if me.home_point is null then
    return jsonb_build_object('players', 0, 'open_hits', 0, 'courts', 0, 'radius_mi', 25, 'area_label', null);
  end if;
  v_reach := greatest(coalesce(me.radius_mi, 10), 25) * 1609.344;
  return jsonb_build_object(
    'radius_mi', greatest(coalesce(me.radius_mi, 10), 25),
    'area_label', me.area_label,
    'players', (
      select count(*) from public.profiles p
      where p.id <> v_user and p.home_point is not null
        and extensions.st_dwithin(p.home_point, me.home_point, v_reach)
        and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
        and not private.hidden_demo(v_user, p.id)
    ),
    'open_hits', (
      select count(*) from public.hits h join public.courts c on c.id = h.court_id
      where h.starts_at < now() + interval '7 days'
        and extensions.st_dwithin(c.point, me.home_point, v_reach)
        and public.feed_candidate(h.id, v_user)
    ),
    'courts', (
      select count(*) from public.courts c
      where not c.hidden and extensions.st_dwithin(c.point, me.home_point, v_reach)
    )
  );
end $$;

revoke execute on function private.is_demo_account(uuid), private.hidden_demo(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.get_area_pulse() from public, anon;
grant execute on function public.get_area_pulse() to authenticated;
