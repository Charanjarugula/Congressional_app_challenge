-- Security hardening from the October 2026 audit.

-- 1. Nothing is callable without an account. These were still executable by the anon role (each
--    checks sign-in inside, but the API shouldn't offer them at all to someone who isn't signed in).
revoke execute on function
  public.cancel_friend_request(uuid),
  public.get_friend_requests(),
  public.report_user(uuid, public.report_reason, text, boolean, uuid, uuid),
  public.respond_friend_request(uuid, boolean),
  public.viewer_can_see_hit(uuid),
  public.viewer_is_active(),
  public.viewer_is_blocked_with(uuid),
  public.viewer_is_chat_member(uuid),
  public.viewer_is_hit_host(uuid)
from public, anon;
grant execute on function
  public.cancel_friend_request(uuid),
  public.get_friend_requests(),
  public.report_user(uuid, public.report_reason, text, boolean, uuid, uuid),
  public.respond_friend_request(uuid, boolean),
  public.viewer_can_see_hit(uuid),
  public.viewer_is_active(),
  public.viewer_is_blocked_with(uuid),
  public.viewer_is_chat_member(uuid),
  public.viewer_is_hit_host(uuid)
to authenticated;


-- 2. A home area is never stored more precisely than about a kilometer, whatever the client sends.
create or replace function private.profiles_round_home() returns trigger
language plpgsql set search_path = public, extensions as $$
begin
  if new.home_point is not null then
    new.home_point := extensions.st_setsrid(extensions.st_makepoint(
      round(extensions.st_x(new.home_point::extensions.geometry)::numeric, 2)::float8,
      round(extensions.st_y(new.home_point::extensions.geometry)::numeric, 2)::float8), 4326);
  end if;
  return new;
end $$;
drop trigger if exists profiles_round_home on public.profiles;
create trigger profiles_round_home before insert or update of home_point on public.profiles
  for each row execute function private.profiles_round_home();

-- 3. Social features need a confirmed adult: a sign-up that hasn't given an 18+ birthday (or was
--    told it's under 18) can't search, add, message or report anyone. A birthday under 18 is
--    remembered, so it can't simply be changed and retried.
alter table public.profiles add column if not exists underage_at timestamptz;

create or replace function private.assert_adult() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); p public.profiles;
begin
  select * into p from public.profiles where id = v_user;
  if p.underage_at is not null then raise exception 'underage'; end if;
  if p.birthday is null or p.birthday > (current_date - interval '18 years') then raise exception 'age_required'; end if;
  return v_user;
end $$;
revoke execute on function private.assert_adult() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.add_friend(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := private.assert_adult(); v_a uuid := least(v_user, p_user); v_b uuid := greatest(v_user, p_user);
  f public.friendships; v_chat uuid;
begin
  if p_user = v_user then raise exception 'cannot_add_self'; end if;
  if not public.is_active_user(p_user) then   -- only finished, active accounts can be asked
    raise exception 'player_unavailable';
  end if;
  if public.is_blocked_either(v_user, p_user) then raise exception 'player_unavailable'; end if;
  perform public.check_rate_limit('add_friend', 60, interval '1 day');

  select * into f from public.friendships where user_a = v_a and user_b = v_b for update;
  if found then
    if f.status = 'accepted' then
      return jsonb_build_object('relationship', 'friend', 'dm_chat_id', f.dm_chat_id);
    elsif f.requested_by = v_user then
      return jsonb_build_object('relationship', 'requested', 'dm_chat_id', null);   -- asked already; asking again is silent
    end if;
    -- They asked first (even if this player had deleted it): adding them is accepting.
    v_chat := public.accept_friendship(v_user, p_user);
    return jsonb_build_object('relationship', 'friend', 'dm_chat_id', v_chat);
  end if;

  insert into public.friendships (user_a, user_b, status, requested_by) values (v_a, v_b, 'pending', v_user);
  perform public.notify(p_user, 'friend_added', 'Courtly', public.display_name(v_user) || ' wants to be friends',
    'courtly://people/requests', 'friend-' || v_user, jsonb_build_object('user_id', v_user));
  return jsonb_build_object('relationship', 'requested', 'dm_chat_id', null);
end $function$;

CREATE OR REPLACE FUNCTION public.respond_friend_request(p_user uuid, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult(); f public.friendships; v_chat uuid;
begin
  select * into f from public.friendships where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user) for update;
  if not found or f.status <> 'pending' or f.requested_by <> p_user or f.declined_at is not null then
    raise exception 'request_not_found';
  end if;
  if p_accept then
    if not public.is_active_user(p_user) or public.is_blocked_either(v_user, p_user) then raise exception 'player_unavailable'; end if;
    v_chat := public.accept_friendship(v_user, p_user);
    return jsonb_build_object('relationship', 'friend', 'dm_chat_id', v_chat);
  end if;
  update public.friendships set declined_at = now() where user_a = f.user_a and user_b = f.user_b;
  delete from public.notifications where user_id = v_user and kind = 'friend_added' and collapse_id = 'friend-' || p_user::text;
  return jsonb_build_object('relationship', 'none', 'dm_chat_id', null);
end $function$;

CREATE OR REPLACE FUNCTION public.search_players(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult(); v_q text := btrim(coalesce(p_query, ''));
begin
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((
    select jsonb_agg(public.player_card(p.id) || jsonb_build_object(
      'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, p.id)),
      'relationship', public.relationship_to(v_user, p.id)
    ) order by p.first_name, p.last_name)
    from (
      select p.* from public.profiles p
      where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
        and not private.hidden_demo(v_user, p.id)
        -- First name, or first name and last initial: never more of the surname than other players see.
        and (p.first_name ilike v_q || '%' or (p.first_name || ' ' || left(p.last_name, 1)) ilike v_q || '%')
      order by p.first_name, p.last_name limit 20
    ) p
  ), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.get_player(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_user uuid := private.assert_adult(); f public.friendships;
begin
  if not public.is_active_user(p_user) or public.is_blocked_either(v_user, p_user) then raise exception 'player_unavailable'; end if;
  select * into f from public.friendships where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user);
  return public.player_card(p_user) || jsonb_build_object(
    'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, p_user)),
    'mutual_cards', public.mutual_friend_cards(v_user, p_user),
    'relationship', public.relationship_to(v_user, p_user),
    'dm_chat_id', case when f.status = 'accepted' then f.dm_chat_id end,
    'friend_count', (select count(*) from public.friendships x where p_user in (x.user_a, x.user_b) and x.status = 'accepted'),
    'hits_together', (select count(*) from public.hit_players a join public.hit_players b on a.hit_id = b.hit_id
                      join public.hits h on h.id = a.hit_id
                      where a.user_id = v_user and b.user_id = p_user and h.status = 'played'),
    'open_hits', coalesce((
      select jsonb_agg(public.hit_json(h.id, v_user) order by h.starts_at)
      from public.hits h
      where h.host_id = p_user and h.status in ('open', 'confirmed') and h.spots_open > 0
        and h.starts_at > now() and public.can_see_hit(h.id, v_user)
    ), '[]'::jsonb)
  );
end $function$;

CREATE OR REPLACE FUNCTION public.match_contacts(p_hashes text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult();
begin
  if cardinality(p_hashes) > 1000 then raise exception 'too_many_hashes'; end if;
  perform public.check_rate_limit('match_contacts', 10, interval '1 day');   -- Add friends re-checks on each visit
  return coalesce((
    select jsonb_agg(jsonb_build_object('hash', h.hash, 'player', public.player_card(p.id),
                                        'relationship', public.relationship_to(v_user, p.id)))
    from unnest(p_hashes) as h(hash)
    join public.profiles p on p.email_hash = h.hash
    where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
      and not private.hidden_demo(v_user, p.id)
  ), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.get_friend_suggestions(p_known_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult();
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
end $function$;

CREATE OR REPLACE FUNCTION public.get_area_pulse()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := private.assert_adult();
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
end $function$;

CREATE OR REPLACE FUNCTION public.report_user(p_user uuid, p_reason report_reason, p_details text DEFAULT NULL::text, p_also_block boolean DEFAULT false, p_hit uuid DEFAULT NULL::uuid, p_message uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult(); m public.messages;
begin
  if p_user = v_user then raise exception 'cannot_report_self'; end if;
  if p_message is not null then
    select * into m from public.messages where id = p_message;
    -- Only a message the reporter could read, written by the player reported.
    if not found or m.sender_id is distinct from p_user or not public.was_chat_member(m.chat_id, v_user) then
      raise exception 'not_a_member';
    end if;
  end if;
  if p_hit is not null and not public.is_hit_member(p_hit, v_user) then raise exception 'not_a_player'; end if;
  perform public.check_rate_limit('report_user', 20, interval '1 day');
  insert into public.reports (reporter_id, reported_id, hit_id, reason, details, also_blocked, message_id, message_body)
  values (v_user, p_user, p_hit, p_reason, left(p_details, 1000), p_also_block, p_message, m.body);
  if p_also_block then perform public.block_user(p_user); end if;
end $function$;

CREATE OR REPLACE FUNCTION public.cancel_friend_request(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult();
begin
  perform public.check_rate_limit('cancel_friend_request', 60, interval '1 day');   -- no add/cancel push loops
  delete from public.friendships
  where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user) and status = 'pending' and requested_by = v_user;
  if not found then raise exception 'request_not_found'; end if;
  delete from public.notifications where user_id = p_user and kind = 'friend_added' and collapse_id = 'friend-' || v_user::text;
  return jsonb_build_object('relationship', 'none', 'dm_chat_id', null);
end $function$;

CREATE OR REPLACE FUNCTION public.get_friend_requests()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult();
begin
  return jsonb_build_object(
    'incoming', coalesce((
      select jsonb_agg(public.player_card(f.requested_by) || jsonb_build_object(
        'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, f.requested_by)),
        'requested_at', f.created_at) order by f.created_at desc)
      from public.friendships f
      where v_user in (f.user_a, f.user_b) and f.status = 'pending' and f.requested_by <> v_user and f.declined_at is null
        and public.is_active_user(f.requested_by) and not public.is_blocked_either(v_user, f.requested_by)
    ), '[]'::jsonb),
    'outgoing', coalesce((
      select jsonb_agg(public.player_card(o.other) || jsonb_build_object(
        'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, o.other)),
        'requested_at', f.created_at) order by f.created_at desc)
      from public.friendships f
      cross join lateral (select case when f.user_a = v_user then f.user_b else f.user_a end as other) o
      where v_user in (f.user_a, f.user_b) and f.status = 'pending' and f.requested_by = v_user
        and public.is_active_user(o.other) and not public.is_blocked_either(v_user, o.other)
    ), '[]'::jsonb)
  );
end $function$;


-- Phone numbers aren't verified, so they no longer match contacts: someone could type in another
-- person's number and show up as them. Matching uses sign-in emails (verified by the code or by
-- Apple or Google). The number stays private on the profile.
update public.profiles set phone_hash = null where phone_hash is not null;

CREATE OR REPLACE FUNCTION public.update_profile(patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_user uuid := public.assert_signed_in(); v_phone text;
begin
  if patch ? 'phone_e164' then
    v_phone := nullif(btrim(coalesce(patch->>'phone_e164', '')), '');
    if v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'invalid_phone'; end if;
  end if;
  if patch ? 'radius_mi' and (patch->>'radius_mi')::int not in (5, 10, 15, 25) then raise exception 'invalid_radius'; end if;
  if patch ? 'hit_visibility' and patch->>'hit_visibility' not in ('anyone', 'friends') then raise exception 'invalid_visibility'; end if;

  update public.profiles set
    first_name = case when patch ? 'first_name' then left(btrim(patch->>'first_name'), 40) else first_name end,
    last_name = case when patch ? 'last_name' then left(btrim(patch->>'last_name'), 40) else last_name end,
    photo_path = case when patch ? 'photo_path' then patch->>'photo_path' else photo_path end,
    birthday = case when patch ? 'birthday' then (patch->>'birthday')::date else birthday end,
    gender = case when patch ? 'gender' then (patch->>'gender')::public.gender else gender end,
    level = case when patch ? 'level' then (patch->>'level')::public.player_level else level end,
    formats = case when patch ? 'formats'
      then (select coalesce(array_agg(value::public.play_format), '{}') from jsonb_array_elements_text(patch->'formats'))
      else formats end,
    zip = case when patch ? 'zip' then patch->>'zip' else zip end,
    area_label = case when patch ? 'area_label' then patch->>'area_label' else area_label end,
    home_point = case when patch ? 'home_lat' and patch ? 'home_lng'
      then extensions.st_setsrid(extensions.st_makepoint((patch->>'home_lng')::float8, (patch->>'home_lat')::float8), 4326)::extensions.geography
      else home_point end,
    radius_mi = case when patch ? 'radius_mi' then (patch->>'radius_mi')::smallint else radius_mi end,
    availability_mask = case when patch ? 'availability_mask' then (patch->>'availability_mask')::int else availability_mask end,
    busy_mask = case when patch ? 'busy_mask' then (patch->>'busy_mask')::int else busy_mask end,
    busy_mask_week = case when patch ? 'busy_mask_week' then (patch->>'busy_mask_week')::int else busy_mask_week end,
    calendar_provider = case when patch ? 'calendar_provider' then (patch->>'calendar_provider')::public.calendar_provider else calendar_provider end,
    phone_e164 = case when patch ? 'phone_e164' then v_phone else phone_e164 end,
    phone_hash = null,
    hit_visibility = case when patch ? 'hit_visibility' then (patch->>'hit_visibility')::public.hit_visibility else hit_visibility end,
    coach_marks_done = case when patch ? 'coach_marks_done' then (patch->>'coach_marks_done')::boolean else coach_marks_done end
  where id = v_user;

  return public.profile_json(v_user);
end $function$;


-- 4. Blocking reaches every hit, not only ones the blocker hosts: a hit with someone you blocked
--    (either way) in it doesn't show, can't be joined, and its players list hides them.

CREATE OR REPLACE FUNCTION public.can_see_hit(p_hit uuid, p_user uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.hits h
    where h.id = p_hit and (
      h.host_id = p_user
      or public.is_hit_member(p_hit, p_user)
      or (
        h.status in ('open', 'confirmed') and h.starts_at > now()   -- strangers only ever see live hits
        and not public.is_blocked_either(p_user, h.host_id)
        and not exists (select 1 from public.hit_players x
                        where x.hit_id = h.id and x.left_at is null and public.is_blocked_either(p_user, x.user_id))
        and public.is_active_user(h.host_id)
        and (
          (h.visibility = 'anyone' and public.host_allows_anyone(h.host_id))
          or (h.visibility in ('anyone', 'friends') and public.is_friend(p_user, h.host_id))
          or public.has_invite_access(p_hit, p_user)
        )
      )
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.feed_candidate(p_hit uuid, p_viewer uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.hits h join public.profiles hp on hp.id = h.host_id
    where h.id = p_hit and h.status in ('open', 'confirmed') and h.spots_open > 0 and h.starts_at > now()
      and h.host_id <> p_viewer and h.visibility <> 'invite_only'
      and hp.suspended_at is null and hp.deleted_at is null and hp.onboarding_completed_at is not null
      and not public.is_blocked_either(p_viewer, h.host_id)
      and not private.hidden_demo(p_viewer, h.host_id)
      and not exists (select 1 from public.hit_players x
                      where x.hit_id = h.id and x.left_at is null and public.is_blocked_either(p_viewer, x.user_id))
      and not exists (select 1 from public.hit_players p where p.hit_id = h.id and p.user_id = p_viewer and p.left_at is null)
      and not exists (select 1 from public.join_requests r where r.hit_id = h.id and r.user_id = p_viewer and r.status in ('pending', 'declined'))
      and ((h.visibility = 'anyone' and hp.hit_visibility = 'anyone') or (h.visibility in ('anyone', 'friends') and public.is_friend(p_viewer, h.host_id)))
  );
$function$;

CREATE OR REPLACE FUNCTION public.add_player(p_hit uuid, p_user uuid, p_source player_source)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.hits; v_chat uuid; r record;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found then raise exception 'hit_not_found'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'hit_full'; end if;
  if h.host_id = p_user then raise exception 'already_in'; end if;
  if exists (select 1 from public.hit_players where hit_id = p_hit and user_id = p_user and left_at is null) then
    raise exception 'already_in';
  end if;
  if not public.is_active_user(p_user) then raise exception 'player_unavailable'; end if;
  if exists (select 1 from public.hit_players x where x.hit_id = p_hit and x.left_at is null
             and public.is_blocked_either(p_user, x.user_id)) then raise exception 'player_unavailable'; end if;
  if public.has_overlapping_hit(p_user, h.starts_at, h.duration_min, p_hit) then raise exception 'overlaps_hit'; end if;

  insert into public.hit_players (hit_id, user_id, role, source) values (p_hit, p_user, 'player', p_source)
  on conflict (hit_id, user_id) do update set left_at = null, joined_at = now(), source = excluded.source;

  update public.hits set spots_open = spots_open - 1, status = 'confirmed' where id = p_hit returning * into h;

  v_chat := public.ensure_hit_chat(p_hit);
  insert into public.chat_members (chat_id, user_id) values (v_chat, p_user)
  on conflict (chat_id, user_id) do update set left_at = null;

  if h.spots_open = 0 then
    update public.hit_invites set status = 'filled' where hit_id = p_hit and status = 'open';
    for r in update public.join_requests set status = 'expired', responded_at = now()
             where hit_id = p_hit and status = 'pending' returning user_id loop
      perform public.notify(r.user_id, 'request_declined', 'Courtly',
        public.hit_push_label(p_hit) || ' filled up before the host could answer you.',
        'courtly://play', 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
    end loop;
  end if;
end $function$;

alter policy hit_players_select on public.hit_players
  using (public.viewer_can_see_hit(hit_id) and not public.viewer_is_blocked_with(user_id));

-- 5. Strangers don't see when someone is free or busy; friends (and the player) still do.

CREATE OR REPLACE FUNCTION public.player_card(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'id', p.id,
    'first_name', p.first_name,
    'last_initial', left(p.last_name, 1),
    'photo_path', p.photo_path,
    'level', p.level,
    'area_label', p.area_label,
    'hits_played', p.hits_played,
    'formats', to_jsonb(p.formats),
    'availability_mask', case when p.id = auth.uid() or public.is_friend(auth.uid(), p.id) then p.availability_mask end,
    'busy_mask_week', case when p.id = auth.uid() or public.is_friend(auth.uid(), p.id) then p.busy_mask_week end
  )
  from public.profiles p where p.id = p_user;
$function$;


-- 6. The player_cards view listed every player to anyone signed in; the app never used it.
revoke select on public.player_cards from authenticated, anon;

-- 7. Tables the app never reads directly are reachable only through its functions. Realtime still
--    needs messages, hits and join_requests, which keep their caller-only rules.
revoke select, insert, update, delete on public.friendships, public.chat_members, public.hit_players, public.blocks,
  public.attendance_checks, public.notifications, public.courts, public.profiles, public.hit_invites, public.device_tokens
from authenticated, anon;
revoke insert, update, delete on public.messages, public.hits, public.join_requests from authenticated, anon;

-- 8. Push tokens: APNs format only, at most 10 per player.

CREATE OR REPLACE FUNCTION public.register_device(p_token text, p_environment text, p_app_version text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := public.assert_signed_in();
begin
  if p_token !~ '^[0-9a-f]{64}$' or p_environment not in ('sandbox', 'production') then raise exception 'invalid_token'; end if;
  insert into public.device_tokens (token, user_id, environment, app_version, updated_at)
  values (p_token, v_user, p_environment, p_app_version, now())
  on conflict (token) do update set user_id = excluded.user_id, environment = excluded.environment,
    app_version = excluded.app_version, updated_at = now();
  delete from public.device_tokens where user_id = v_user and token not in (
    select token from public.device_tokens where user_id = v_user order by updated_at desc limit 10);
end $function$;


-- 9. Deleting an unfinished account keeps reports filed about it (moderation evidence until the 90-day purge).

CREATE OR REPLACE FUNCTION public.internal_delete_account(p_user uuid, p_mode text DEFAULT 'full'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_hit public.hits; v_vault uuid; v_mode text := p_mode;
begin
  select vault_secret_id into v_vault from public.apple_tokens where user_id = p_user;

  -- The underage path removes everything outright. It is for an account that never finished onboarding;
  -- one that did has hits, chats and answers other players rely on, and gets the full path whatever it asked.
  if v_mode = 'underage' and exists (select 1 from public.profiles where id = p_user and onboarding_completed_at is not null) then
    v_mode := 'full';
  end if;

  if v_mode = 'underage' then
    -- Someone under 13 never finished onboarding; nothing of theirs stays, not even an anonymized row.
    -- They may already have sent friend requests (which open DMs), blocked or reported someone.
    delete from public.device_tokens where user_id = p_user;
    delete from public.notifications where user_id = p_user;
    delete from public.join_requests where user_id = p_user;
    delete from public.hit_invites where created_by = p_user or target_user_id = p_user;
    delete from public.friendships where p_user in (user_a, user_b);
    delete from public.blocks where p_user in (blocker_id, blocked_id);
    delete from public.reports where reporter_id = p_user;   -- reports about them stay
    delete from public.attendance_checks where p_user in (user_id, about_user_id);
    delete from public.rate_limits where user_id = p_user;
    delete from public.apple_tokens where user_id = p_user;
    delete from public.admin_users where user_id = p_user;
    if v_vault is not null then delete from vault.secrets where id = v_vault; end if;
    for r in select c.id from public.chats c join public.chat_members m on m.chat_id = c.id where c.type = 'dm' and m.user_id = p_user loop
      update public.chats set last_message_id = null where id = r.id;
      delete from public.messages where chat_id = r.id;
      delete from public.chat_members where chat_id = r.id;
      delete from public.chats where id = r.id;
    end loop;
    delete from public.messages where sender_id = p_user;
    delete from public.chat_members where user_id = p_user;
    delete from public.hit_players where user_id = p_user;
    delete from public.hits where host_id = p_user;
    delete from public.profiles where id = p_user;
    return jsonb_build_object('deleted', true);
  end if;

  -- Future hits I host are cancelled; future hits I joined are left. Each hit is locked and looked at
  -- again first: a leave or a cancel landing at the same moment must not release the spot twice or
  -- reopen a cancelled hit.
  for r in select id from public.hits where host_id = p_user and status in ('open', 'confirmed') and starts_at > now() loop
    perform public.close_hit(r.id, 'The host left Courtly.');
  end loop;
  for r in select h.id from public.hits h join public.hit_players hp on hp.hit_id = h.id
           where hp.user_id = p_user and hp.role = 'player' and hp.left_at is null and h.status in ('open', 'confirmed') and h.starts_at > now() loop
    select * into v_hit from public.hits where id = r.id for update;
    if v_hit.status not in ('open', 'confirmed') or v_hit.starts_at <= now() then continue; end if;
    update public.hit_players set left_at = now() where hit_id = v_hit.id and user_id = p_user and left_at is null;
    if not found then continue; end if;
    update public.hits set spots_open = spots_open + 1,
      status = case when exists (select 1 from public.hit_players x where x.hit_id = v_hit.id and x.role = 'player' and x.left_at is null)
                    then status else 'open' end
    where id = v_hit.id;
    perform public.notify(v_hit.host_id, 'player_left', 'Courtly', 'A player left ' || public.hit_push_label(v_hit.id) || '. The spot is open again.',
      'courtly://hit/' || v_hit.id, 'hit-' || v_hit.id, jsonb_build_object('hit_id', v_hit.id));
  end loop;

  delete from public.device_tokens where user_id = p_user;
  delete from public.notifications where user_id = p_user;
  delete from public.join_requests where user_id = p_user;
  delete from public.hit_invites where created_by = p_user or target_user_id = p_user;
  delete from public.friendships where p_user in (user_a, user_b);
  delete from public.blocks where p_user in (blocker_id, blocked_id);
  -- Day-after answers stay: they are about other players, and the one that counted an absence must not
  -- vanish, or the next "No" would count it again.
  delete from public.rate_limits where user_id = p_user;
  delete from public.apple_tokens where user_id = p_user;
  delete from public.admin_users where user_id = p_user;
  if v_vault is not null then delete from vault.secrets where id = v_vault; end if;

  -- Direct messages go; group and hit chats keep the thread with my messages anonymized.
  for r in select c.id from public.chats c join public.chat_members m on m.chat_id = c.id where c.type = 'dm' and m.user_id = p_user loop
    update public.chats set last_message_id = null where id = r.id;
    delete from public.messages where chat_id = r.id;
    delete from public.chat_members where chat_id = r.id;
    delete from public.chats where id = r.id;
  end loop;
  update public.messages set sender_id = null where sender_id = p_user;
  for r in select chat_id from public.chat_members where user_id = p_user and left_at is null loop
    update public.chat_members set left_at = now() where chat_id = r.chat_id and user_id = p_user;
    perform public.system_message(r.chat_id, 'A player left Courtly', jsonb_build_object('event', 'member_left'));
  end loop;

  update public.profiles set
    first_name = 'Deleted', last_name = '', photo_path = null, birthday = null, gender = null,
    phone_e164 = null, phone_hash = null, email_hash = null, home_point = null, zip = null, area_label = null,
    availability_mask = 0, busy_mask_week = null, deleted_at = now()
  where id = p_user;
  return jsonb_build_object('deleted', true);
end $function$;


-- 10. Court lists are capped.

CREATE OR REPLACE FUNCTION public.get_nearby_courts(p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with me as (select home_point from public.profiles where id = public.assert_signed_in()),
  ranked as (
    select c.id, extensions.st_distance(c.point, me.home_point) as metres,
           (select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
            where h.court_id = c.id and hp.user_id = auth.uid() and h.status = 'played') as played_count
    from public.courts c, me
    where c.hidden = false and me.home_point is not null
    order by played_count desc, metres limit least(greatest(coalesce(p_limit, 30), 1), 100)
  )
  select coalesce(jsonb_agg(public.court_json(r.id) || jsonb_build_object(
           'miles', round((r.metres / 1609.344)::numeric, 1), 'played_count', r.played_count)
         order by r.played_count desc, r.metres), '[]'::jsonb)
  from ranked r;
$function$;


-- 11. Profile guard: photos only as <own id>/<name>.jpg|png (no ../), names and area filtered and
--     length-capped, birthday under 18 remembered, home area changes rate-limited.
create or replace function private.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.photo_path is distinct from old.photo_path and new.photo_path is not null
     and new.photo_path !~ ('^' || new.id::text || '/[A-Za-z0-9_-]+\.(jpg|png)$') then
    raise exception 'invalid_photo';
  end if;
  if new.birthday is distinct from old.birthday then
    if old.underage_at is not null then raise exception 'underage'; end if;
    if new.birthday > (current_date - interval '18 years') then
      if new.onboarding_completed_at is not null then raise exception 'underage'; end if;
      new.underage_at := now();
    end if;
  end if;
  if new.first_name is distinct from old.first_name or new.last_name is distinct from old.last_name
     or new.area_label is distinct from old.area_label then
    if length(new.first_name) > 40 or length(new.last_name) > 40 or length(new.area_label) > 80 then
      raise exception 'too_long';
    end if;
    perform public.filter_text(concat_ws(' ', new.first_name, new.last_name, new.area_label));
  end if;
  if length(new.zip) > 10 then raise exception 'too_long'; end if;
  if new.home_point is distinct from old.home_point and auth.uid() = new.id and old.home_point is not null then
    perform public.check_rate_limit('home_area', 10, interval '1 day');
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function private.profiles_guard();


-- 12. New functions in public are not executable by everyone by default (the per-schema revoke in
--     0009 can't remove PUBLIC's global default; this does, for the role that runs migrations).
do $$ begin
  execute format('alter default privileges for role %I revoke execute on functions from public', current_user);
end $$;
