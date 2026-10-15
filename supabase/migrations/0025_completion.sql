-- Completion pass: time zones that follow the court, editing a hit, a frozen member list for people
-- who left a group, and no more phone numbers.

-- 1. Time zones. A hit happens at a court, so its times read in the court's zone (from Apple Maps when
--    the court is added; existing courts are Eastern). A player's free/busy blocks are in their own
--    zone (the device's, kept on the profile).
alter table public.courts add column if not exists time_zone text not null default 'America/New_York';
alter table public.profiles add column if not exists time_zone text not null default 'America/New_York';

create or replace function private.valid_time_zone(p_tz text) returns boolean
language sql stable as $$ select exists (select 1 from pg_timezone_names where name = p_tz) $$;

create or replace function private.time_zone_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if not private.valid_time_zone(new.time_zone) then raise exception 'invalid_time_zone'; end if;
  return new;
end $$;
drop trigger if exists courts_time_zone on public.courts;
create trigger courts_time_zone before insert or update of time_zone on public.courts
  for each row execute function private.time_zone_guard();
drop trigger if exists profiles_time_zone on public.profiles;
create trigger profiles_time_zone before insert or update of time_zone on public.profiles
  for each row execute function private.time_zone_guard();

create or replace function public.court_time_zone(p_court uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select time_zone from public.courts where id = p_court), 'America/New_York');
$$;
create or replace function public.player_time_zone(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select time_zone from public.profiles where id = p_user), 'America/New_York');
$$;

drop function if exists public.time_label(timestamptz);
create or replace function public.time_label(p_at timestamptz, p_tz text default 'America/New_York') returns text
language sql stable set search_path = public as $$
  select to_char(p_at at time zone p_tz, 'Dy FMHH12:MI AM');
$$;

drop function if exists public.availability_bit(timestamptz);
create or replace function public.availability_bit(p_at timestamptz, p_tz text default 'America/New_York') returns integer
language sql stable as $$
  select case
    when extract(hour from local) between 7 and 10 then (extract(isodow from local)::int - 1) * 3
    when extract(hour from local) between 12 and 15 then (extract(isodow from local)::int - 1) * 3 + 1
    when extract(hour from local) between 17 and 20 then (extract(isodow from local)::int - 1) * 3 + 2
    end
  from (select p_at at time zone p_tz as local) t;
$$;


drop function if exists public.remaining_week_mask();
create or replace function public.remaining_week_mask(p_tz text default 'America/New_York') returns integer
language sql stable as $$
  -- Between two blocks the next one today still counts; after the evening, tomorrow's morning is first.
  select coalesce(bit_or(1 << (d * 3 + b)), 0)::integer
  from generate_series(0, 6) d, generate_series(0, 2) b, (select now() at time zone p_tz as local) t
  where (d * 3 + b) >= (extract(isodow from local)::int - 1) * 3 + case
    when extract(hour from local) < 11 then 0
    when extract(hour from local) < 16 then 1
    when extract(hour from local) < 21 then 2
    else 3 end;
$$;

create or replace function public.hit_push_label(p_hit uuid) returns text
language sql stable security definer set search_path = public as $$
  select public.time_label(h.starts_at, c.time_zone) || ' at ' || c.name
  from public.hits h join public.courts c on c.id = h.court_id where h.id = p_hit;
$$;

create or replace function public.hit_chat_label(p_hit uuid) returns text
language sql stable security definer set search_path = public as $$
  select initcap(h.format::text) || ' · ' || public.time_label(h.starts_at, c.time_zone) || ' · ' || c.name
  from public.hits h join public.courts c on c.id = h.court_id where h.id = p_hit;
$$;

create or replace function public.busy_at(p_user uuid, p_at timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select (p.busy_mask
            | case when p_at < now() + interval '7 days' and p.busy_mask_week_at > now() - interval '7 days'
                   then coalesce(p.busy_mask_week, 0) else 0 end) & (1 << bit) <> 0
    from public.profiles p, lateral (select public.availability_bit(p_at, p.time_zone) as bit) b
    where p.id = p_user and b.bit is not null
  ), false);
$$;

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
  v_bit := public.availability_bit(h.starts_at, me.time_zone);
  if v_bit is not null and (me.availability_mask & (1 << v_bit)) <> 0 then
    return 'Fits your ' || to_char(h.starts_at at time zone me.time_zone, 'FMDay');
  end if;
  select p.first_name into v_mutual from public.profiles p
  where p.id <> p_viewer and p.id <> h.host_id and public.is_friend(p_viewer, p.id) and public.is_friend(h.host_id, p.id) limit 1;
  if v_mutual is not null then return 'Friend of ' || v_mutual; end if;
  if p_is_closest then return 'Closest court to you'; end if;
  return null;
end $$;

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
          and not public.busy_at(v_user, h.starts_at)
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
          and not public.busy_at(v_user, h.starts_at)
          and me.home_point is not null and extensions.st_dwithin(c.point, me.home_point, me.radius_mi * 1609.344)
        order by rn limit 30
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
      select b.user_id, 'played', 3, 0, 'You hit together on ' || to_char(h.starts_at at time zone public.court_time_zone(h.court_id), 'Mon FMDD')
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
               when nh.starts_at is not null then 'Hosting a hit ' || to_char(nh.starts_at at time zone nh.time_zone, 'FMDay')
               when p.level = me.level and (p.availability_mask & me.availability_mask) <> 0 then 'Your level, free when you are'
               when p.level = me.level then 'Your level, plays near you'
               else 'Plays near you'
             end
      from public.profiles p
      cross join me
      left join lateral (
        select h.starts_at, public.court_time_zone(h.court_id) as time_zone from public.hits h
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

create or replace function public.send_hit_invite(
  p_hit uuid, p_chat uuid, p_target_user uuid default null, p_expires_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.assert_onboarded(); h public.hits; v_invite uuid; v_message uuid; v_expires timestamptz;
  v_evening_before timestamptz; v_body text; m record; c public.chats; v_other uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.host_id <> v_user then raise exception 'not_host'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'hit_full'; end if;
  if not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  select * into c from public.chats where id = p_chat;
  if c.type = 'dm' then
    -- Same gate as a text message: a DM carries hit requests only once both players added each other.
    select user_id into v_other from public.chat_members where chat_id = p_chat and user_id <> v_user limit 1;
    if public.is_blocked_either(v_user, v_other) then raise exception 'player_unavailable'; end if;
    if not public.is_friend(v_user, v_other) then raise exception 'not_friends'; end if;
  end if;
  perform public.check_rate_limit('send_hit_invite', 20, interval '1 minute');
  if p_target_user is not null then
    if not public.is_chat_member(p_chat, p_target_user) then raise exception 'not_a_member'; end if;
    if public.is_blocked_either(v_user, p_target_user) then raise exception 'player_unavailable'; end if;
    if public.is_hit_member(p_hit, p_target_user) then raise exception 'already_in'; end if;
  end if;

  -- Default expiry: 8 PM the evening before, or two hours before start, whichever is sooner; never in the past.
  v_evening_before := (date_trunc('day', h.starts_at at time zone public.court_time_zone(h.court_id)) - interval '1 day' + interval '20 hours')
                      at time zone public.court_time_zone(h.court_id);
  v_expires := coalesce(p_expires_at, least(h.starts_at - interval '2 hours', v_evening_before));
  if v_expires <= now() then v_expires := least(h.starts_at - interval '5 minutes', now() + interval '12 hours'); end if;
  if v_expires >= h.starts_at then raise exception 'invalid_expiry'; end if;

  insert into public.hit_invites (hit_id, chat_id, created_by, target_user_id, spots, expires_at)
  values (p_hit, p_chat, v_user, p_target_user, h.spots_open, v_expires) returning id into v_invite;

  v_message := public.post_message(p_chat, v_user, 'hit_invite',
    'Hit request: ' || public.hit_push_label(p_hit),
    jsonb_build_object('invite_id', v_invite, 'hit_id', p_hit));
  update public.hit_invites set message_id = v_message where id = v_invite;

  if p_target_user is not null then
    perform public.notify(p_target_user, 'hit_invite', 'Courtly',
      public.display_name(v_user) || ' invited you · ' || public.hit_push_label(p_hit),
      'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit, 'invite_id', v_invite, 'chat_id', p_chat));
  else
    v_body := public.display_name(v_user) || ' needs ' || h.spots_open || ' for ' || public.hit_push_label(p_hit);
    for m in select cm.user_id from public.chat_members cm
             where cm.chat_id = p_chat and cm.left_at is null and cm.muted = false and cm.user_id <> v_user
               and not public.is_blocked_either(v_user, cm.user_id) loop
      perform public.notify(m.user_id, 'message', coalesce((select name from public.chats where id = p_chat), 'Courtly'),
        v_body, 'courtly://chat/' || p_chat, 'chat-' || p_chat, jsonb_build_object('chat_id', p_chat, 'hit_id', p_hit));
    end loop;
  end if;
  return public.invite_json(v_invite, v_user);
end $$;

create or replace function public.run_hit_scheduler() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  -- Open hits nobody joined, now in the past.
  for r in update public.hits set status = 'expired' where status = 'open' and starts_at < now() returning id loop
    update public.join_requests set status = 'expired', responded_at = now() where hit_id = r.id and status = 'pending';
    update public.hit_invites set status = 'expired' where hit_id = r.id and status = 'open';
  end loop;

  -- Invite cards past their deadline.
  for r in update public.hit_invites set status = 'expired' where status = 'open' and expires_at < now() returning id, chat_id loop
    perform public.system_message(r.chat_id, 'Hit request closed', jsonb_build_object('event', 'invite_expired', 'invite_id', r.id));
  end loop;

  -- Confirmed hits that have finished.
  for r in update public.hits set status = 'played'
           where status = 'confirmed' and starts_at + (duration_min || ' minutes')::interval < now() returning id loop
    update public.join_requests set status = 'expired', responded_at = now() where hit_id = r.id and status = 'pending';
    update public.profiles p set hits_played = hits_played + 1
    from public.hit_players hp where hp.hit_id = r.id and hp.left_at is null and p.id = hp.user_id;
  end loop;

  -- Day-before reminder.
  for r in update public.hits set reminder_day_sent_at = now()
           where status = 'confirmed' and reminder_day_sent_at is null
             and starts_at <= now() + interval '24 hours 5 minutes' and starts_at > now() + interval '1 hour'
             and created_at <= starts_at - interval '24 hours'
           returning id loop
    perform public.notify(hp.user_id, 'reminder_day', 'Hit tomorrow',
      public.hit_push_label(r.id) || ' · ' || coalesce((select string_agg(public.display_name(o.user_id), ', ')
        from public.hit_players o where o.hit_id = r.id and o.left_at is null and o.user_id <> hp.user_id), ''),
      'courtly://hit/' || r.id, 'hit-' || r.id, jsonb_build_object('hit_id', r.id))
    from public.hit_players hp where hp.hit_id = r.id and hp.left_at is null;
  end loop;

  -- One-hour reminder.
  for r in update public.hits set reminder_hour_sent_at = now()
           where status = 'confirmed' and reminder_hour_sent_at is null
             and starts_at <= now() + interval '65 minutes' and starts_at > now()
           returning id loop
    perform public.notify(hp.user_id, 'reminder_hour', 'Hit in 1 hour', public.hit_push_label(r.id),
      'courtly://hit/' || r.id, 'hit-' || r.id, jsonb_build_object('hit_id', r.id))
    from public.hit_players hp where hp.hit_id = r.id and hp.left_at is null;
  end loop;

  -- Day-after check, from 9 AM the day after in the court's zone.
  begin
    for r in update public.hits set day_after_sent_at = now()
             where status = 'played' and day_after_sent_at is null
               and (starts_at at time zone public.court_time_zone(court_id))::date < (now() at time zone public.court_time_zone(court_id))::date
               and extract(hour from now() at time zone public.court_time_zone(court_id)) >= 9
             returning id loop
      perform public.notify(hp.user_id, 'day_after_check', 'Courtly',
        'Did ' || public.display_name(o.user_id) || ' show up?',
        'courtly://check/' || r.id || '/' || o.user_id, 'check-' || r.id,
        jsonb_build_object('hit_id', r.id, 'about_user_id', o.user_id))
      from public.hit_players hp
      join public.hit_players o on o.hit_id = hp.hit_id and o.user_id <> hp.user_id and o.left_at is null
      where hp.hit_id = r.id and hp.left_at is null;
    end loop;
  end;
end $$;

create or replace function public.court_json(p_court uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'address', c.address, 'city', c.city,
    'lat', extensions.st_y(c.point::extensions.geometry), 'lng', extensions.st_x(c.point::extensions.geometry),
    'surface', c.surface, 'lights', c.lights, 'time_zone', c.time_zone
  )
  from public.courts c where c.id = p_court;
$$;

create or replace function public.profile_json(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', p.id, 'first_name', p.first_name, 'last_name', p.last_name, 'photo_path', p.photo_path,
    'birthday', p.birthday, 'gender', p.gender, 'level', p.level, 'formats', to_jsonb(p.formats),
    'zip', p.zip, 'area_label', p.area_label,
    'home_lat', extensions.st_y(p.home_point::extensions.geometry), 'home_lng', extensions.st_x(p.home_point::extensions.geometry),
    'radius_mi', p.radius_mi, 'availability_mask', p.availability_mask, 'busy_mask', p.busy_mask, 'busy_mask_week', p.busy_mask_week,
    'calendar_provider', p.calendar_provider, 'phone_e164', p.phone_e164, 'hit_visibility', p.hit_visibility,
    'hits_played', p.hits_played, 'time_zone', p.time_zone, 'coach_marks_done', p.coach_marks_done,
    'onboarding_completed_at', p.onboarding_completed_at,
    'blocked_count', (select count(*) from public.blocks b where b.blocker_id = p.id)
  )
  from public.profiles p where p.id = p_user;
$$;

drop function if exists public.add_court(text, text, text, double precision, double precision, text, text, boolean);
create or replace function public.add_court(
  p_name text, p_address text, p_city text, p_lat float8, p_lng float8,
  p_apple_place_id text default null, p_surface text default null, p_lights boolean default null,
  p_time_zone text default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_onboarded(); v_point extensions.geography; v_id uuid;
        v_tz text := coalesce(nullif(btrim(p_time_zone), ''), public.player_time_zone(v_user));
begin
  if btrim(coalesce(p_name, '')) = '' then raise exception 'missing_name'; end if;
  if not private.valid_time_zone(v_tz) then v_tz := public.player_time_zone(v_user); end if;
  perform public.check_rate_limit('add_court', 20, interval '1 day');
  v_point := extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;

  if p_apple_place_id is not null then
    select id into v_id from public.courts where apple_place_id = p_apple_place_id;
  end if;
  if v_id is null then
    select id into v_id from public.courts c
    where extensions.st_dwithin(c.point, v_point, 100) and extensions.similarity(lower(c.name), lower(p_name)) > 0.4
    order by extensions.st_distance(c.point, v_point) limit 1;
  end if;
  if v_id is null then
    insert into public.courts (name, address, city, point, surface, lights, source, apple_place_id, created_by, time_zone)
    values (left(btrim(p_name), 80), left(p_address, 200), left(p_city, 80), v_point, p_surface, p_lights,
            (case when p_apple_place_id is null then 'user' else 'apple_maps' end)::public.court_source, p_apple_place_id, v_user, v_tz)
    returning id into v_id;
  elsif p_apple_place_id is not null then
    update public.courts set apple_place_id = coalesce(apple_place_id, p_apple_place_id) where id = v_id;
  end if;
  return public.court_json(v_id);
end $$;

revoke execute on function public.add_court(text, text, text, double precision, double precision, text, text, boolean, text) from public, anon;
grant execute on function public.add_court(text, text, text, double precision, double precision, text, text, boolean, text) to authenticated;
revoke execute on function public.court_time_zone(uuid), public.player_time_zone(uuid), public.time_label(timestamptz, text),
  public.availability_bit(timestamptz, text), public.remaining_week_mask(text) from public, anon, authenticated;
revoke execute on function private.valid_time_zone(text) from public, anon, authenticated;

-- The app keeps the profile's zone in step with the device.

CREATE OR REPLACE FUNCTION public.update_profile(patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_user uuid := public.assert_signed_in(); v_phone text;
begin
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
    -- the app sends the iPhone's zone; one Postgres doesn't know keeps the last good one instead of failing onboarding
    time_zone = case when private.valid_time_zone(patch->>'time_zone') then patch->>'time_zone' else time_zone end,
    phone_e164 = null,   -- no longer collected (2. below)
    phone_hash = null,
    hit_visibility = case when patch ? 'hit_visibility' then (patch->>'hit_visibility')::public.hit_visibility else hit_visibility end,
    coach_marks_done = case when patch ? 'coach_marks_done' then (patch->>'coach_marks_done')::boolean else coach_marks_done end
  where id = v_user;

  return public.profile_json(v_user);
end $function$;


-- 2. Phone numbers are no longer collected: unverified, never shown, and used for nothing after
--    contact matching moved to verified emails (App Review 5.1.1(iii): collect only what a feature needs).
update public.profiles set phone_e164 = null, phone_hash = null where phone_e164 is not null or phone_hash is not null;

-- 3. Someone who left a group keeps the history up to leaving and sees the members as they were then,
--    not who joined after.

create or replace function public.chat_json(p_chat uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'type', c.type, 'name', public.chat_display_name(c.id, p_viewer), 'hit_id', public.chat_pinned_hit(c.id),
    'members', (select jsonb_agg(public.player_card(m.user_id) order by m.joined_at)
                from public.chat_members m where m.chat_id = c.id and (
                  (me.left_at is null and m.left_at is null)
                  or (me.left_at is not null and m.user_id <> p_viewer and m.joined_at <= me.left_at
                      and (m.left_at is null or m.left_at >= me.left_at)))),
    'member_count', (select count(*) from public.chat_members m where m.chat_id = c.id and (
                  (me.left_at is null and m.left_at is null)
                  or (me.left_at is not null and m.user_id <> p_viewer and m.joined_at <= me.left_at
                      and (m.left_at is null or m.left_at >= me.left_at)))),
    'last_message_at', least(c.last_message_at, me.left_at),
    'last_message_type', lm.type,
    'preview', case
      when lm.id is null then null
      when lm.type = 'system' then left(public.message_text(lm.id, p_viewer), 120)
      when lm.type = 'text' and lm.sender_id is not null then public.display_name(lm.sender_id) || ': ' || left(lm.body, 120)
      else left(lm.body, 120) end,
    'unread_count', least(99, (
      select count(*) from public.messages m
      where m.chat_id = c.id and m.sender_id is distinct from p_viewer
        and m.created_at > coalesce(me.last_read_at, '-infinity'::timestamptz)
        and (me.left_at is null or m.created_at <= me.left_at)
        and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id)))),
    'muted', me.muted,
    'left_at', me.left_at,
    'friendship', case when c.type = 'dm' then public.relationship_to(p_viewer,
      (select m.user_id from public.chat_members m where m.chat_id = c.id and m.user_id <> p_viewer limit 1)) end,
    'hit', case when me.left_at is not null or public.chat_pinned_hit(c.id) is null then null else public.hit_json(public.chat_pinned_hit(c.id), p_viewer) end
  )
  from public.chats c
  join public.chat_members me on me.chat_id = c.id and me.user_id = p_viewer
  left join lateral (
    select m.id, m.type, m.sender_id, m.body from public.messages m
    where m.id = c.last_message_id and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id))
      and (me.left_at is null or m.created_at <= me.left_at)
    union all
    (select m.id, m.type, m.sender_id, m.body from public.messages m
     where m.chat_id = c.id and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id))
       and (me.left_at is null or m.created_at <= me.left_at)
     order by m.created_at desc, m.id desc limit 1)
    limit 1
  ) lm on true
  where c.id = p_chat;
$$;


-- 4. Editing a hit. The host can change the time, court, length, format, spots and who can join while
--    it hasn't started. Everyone already in (and anyone waiting on a request) hears about a new time or
--    court, and the hit chat says what changed.
alter type public.notification_kind add value if not exists 'hit_changed';

create or replace function public.update_hit(
  p_hit uuid, p_court_id uuid, p_starts_at timestamptz, p_duration_min integer, p_format public.play_format,
  p_spots integer, p_visibility public.hit_visibility
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.assert_onboarded(); h public.hits; v_players integer; v_visibility public.hit_visibility := p_visibility;
  v_moved boolean; v_label text; r record;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.host_id <> v_user then raise exception 'not_host'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if p_starts_at <= now() + interval '15 minutes' then raise exception 'starts_in_past'; end if;
  if p_starts_at > now() + interval '30 days' then raise exception 'too_far_ahead'; end if;
  if p_duration_min not in (60, 90, 120) then raise exception 'invalid_duration'; end if;
  if not exists (select 1 from public.courts where id = p_court_id and hidden = false) then raise exception 'court_not_found'; end if;
  select count(*) into v_players from public.hit_players where hit_id = p_hit and left_at is null and role = 'player';
  if p_spots not between greatest(1, v_players) and 7 then raise exception 'invalid_spots'; end if;
  if public.has_overlapping_hit(v_user, p_starts_at, p_duration_min, p_hit) then raise exception 'overlaps_hit'; end if;
  perform public.check_rate_limit('update_hit', 30, interval '1 day');
  if v_visibility = 'anyone' and not public.host_allows_anyone(v_user) then v_visibility := 'friends'; end if;

  v_moved := p_starts_at <> h.starts_at or p_court_id <> h.court_id;
  update public.hits set court_id = p_court_id, starts_at = p_starts_at, duration_min = p_duration_min, format = p_format,
    spots_total = p_spots, spots_open = p_spots - v_players, visibility = v_visibility,
    -- a new time gets its own reminders
    reminder_day_sent_at = case when p_starts_at <> h.starts_at then null else reminder_day_sent_at end,
    reminder_hour_sent_at = case when p_starts_at <> h.starts_at then null else reminder_hour_sent_at end
  where id = p_hit returning * into h;
  if h.spots_open = 0 then
    update public.hit_invites set status = 'filled' where hit_id = p_hit and status = 'open';
  end if;

  if v_moved then
    v_label := public.hit_push_label(p_hit);
    if h.chat_id is not null then
      perform public.system_message(h.chat_id, public.display_name(v_user) || ' moved the hit to ' || v_label,
        jsonb_build_object('event', 'hit_changed', 'actor', v_user, 'hit_id', p_hit));
    end if;
    for r in
      select hp.user_id from public.hit_players hp where hp.hit_id = p_hit and hp.left_at is null and hp.user_id <> v_user
      union
      select jr.user_id from public.join_requests jr where jr.hit_id = p_hit and jr.status = 'pending'
    loop
      perform public.notify(r.user_id, 'hit_changed', 'Hit moved', public.display_name(v_user) || ' moved it to ' || v_label,
        'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
    end loop;
  end if;
  return public.hit_json(p_hit, v_user);
end $$;
revoke execute on function public.update_hit(uuid, uuid, timestamptz, integer, public.play_format, integer, public.hit_visibility) from public, anon;
grant execute on function public.update_hit(uuid, uuid, timestamptz, integer, public.play_format, integer, public.hit_visibility) to authenticated;

-- 5. The host reads "You moved the hit to …" in the hit chat, like the other events they cause.
create or replace function public.message_text(p_message uuid, p_viewer uuid default auth.uid()) returns text
language sql stable security definer set search_path = public as $$
  select case
    when m.type <> 'system' then m.body
    when m.payload->>'event' = 'friend_added' and (m.payload->>'actor')::uuid = p_viewer
      then 'You added ' || public.display_name((m.payload->>'subject')::uuid)
    when m.payload->>'event' = 'friend_added' and (m.payload->>'subject')::uuid = p_viewer
      then public.display_name((m.payload->>'actor')::uuid) || ' added you'
    when m.payload->>'event' = 'friend_accepted' and (m.payload->>'actor')::uuid = p_viewer
      then 'You and ' || public.display_name((m.payload->>'subject')::uuid) || ' are now friends. Say hi'
    when m.payload->>'event' = 'friend_accepted' and (m.payload->>'subject')::uuid = p_viewer
      then public.display_name((m.payload->>'actor')::uuid) || ' accepted your request. Say hi'
    when m.payload->>'event' = 'request_accepted' and (m.payload->>'actor')::uuid = p_viewer
      then 'You accepted ' || public.display_name((m.payload->>'subject')::uuid) || '’s request to join'
    when m.payload->>'event' = 'request_accepted' and (m.payload->>'subject')::uuid = p_viewer
      then public.display_name((m.payload->>'actor')::uuid) || ' accepted your request to join'
    when m.payload->>'event' = 'host_changed' and (m.payload->>'subject')::uuid = p_viewer
      then public.display_name((m.payload->>'actor')::uuid) || ' left the hit · you’re hosting now'
    when m.payload->>'event' in ('player_left', 'member_left', 'hit_cancelled', 'host_changed', 'hit_changed') and (m.payload->>'actor')::uuid = p_viewer
      then 'You ' || substring(m.body from length(public.display_name((m.payload->>'actor')::uuid)) + 2)
    else m.body end
  from public.messages m where m.id = p_message;
$$;
