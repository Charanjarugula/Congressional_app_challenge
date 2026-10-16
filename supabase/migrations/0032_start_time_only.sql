-- Start-only hits have no promised end time. Keep existing fixed-length hits intact.
alter table public.hits alter column duration_min drop not null;

-- This is a history/attendance cutoff, NOT an estimated playing duration.
-- Start-only hits move into history at the next midnight in the court's zone.
create or replace function public.hit_archive_at(p_start timestamptz, p_duration integer, p_court uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select case when p_duration is not null then p_start + make_interval(mins => p_duration)
    else (date_trunc('day', p_start at time zone c.time_zone) + interval '1 day') at time zone c.time_zone end
  from public.courts c where c.id = p_court;
$$;
revoke all on function public.hit_archive_at(timestamptz, integer, uuid) from public, anon, authenticated;

create or replace function public.hit_json(p_hit uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', h.id,
    'host', public.player_card(h.host_id),
    'court', public.court_json(h.court_id),
    'starts_at', h.starts_at,
    'duration_min', coalesce(h.duration_min, 90), -- compatibility for installed clients decoding a non-null integer
    'start_time_only', h.duration_min is null,
    'format', h.format,
    'spots_total', h.spots_total,
    'spots_open', h.spots_open,
    'visibility', h.visibility,
    'status', h.status,
    'chat_id', h.chat_id,
    'needs_attendance', case when h.status = 'played' then public.needs_attendance(h.id, p_viewer) else false end,
    'players', coalesce((
      select jsonb_agg(public.player_card(hp.user_id) || jsonb_build_object('role', hp.role) order by hp.joined_at)
      from public.hit_players hp where hp.hit_id = h.id and hp.left_at is null and hp.role = 'player'
    ), '[]'::jsonb),
    'miles', (
      select round((extensions.st_distance(c.point, p.home_point) / 1609.344)::numeric, 1)
      from public.courts c, public.profiles p where c.id = h.court_id and p.id = p_viewer
    ),
    'pending_request_count', case when h.host_id = p_viewer
      then (select count(*) from public.join_requests r where r.hit_id = h.id and r.status = 'pending') else 0 end,
    'unread_messages', (
      select count(*) from public.messages m
      join public.chat_members cm on cm.chat_id = m.chat_id and cm.user_id = p_viewer
      where m.chat_id = h.chat_id and m.sender_id is distinct from p_viewer
        and m.created_at > coalesce(cm.last_read_at, '-infinity'::timestamptz)
    ),
    'viewer', jsonb_build_object(
      'is_host', h.host_id = p_viewer,
      'is_player', exists (select 1 from public.hit_players hp where hp.hit_id = h.id and hp.user_id = p_viewer and hp.left_at is null),
      'request', (
        select jsonb_build_object('id', r.id, 'status', r.status, 'seen', r.seen_by_requester_at is not null)
        from public.join_requests r where r.hit_id = h.id and r.user_id = p_viewer order by r.created_at desc limit 1
      ),
      'invite', (
        select jsonb_build_object('id', i.id, 'status', i.status, 'expires_at', i.expires_at)
        from public.hit_invites i where i.hit_id = h.id and i.target_user_id = p_viewer and i.status = 'open'
        order by i.created_at desc limit 1
      ),
      'attendance', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', a.about_user_id, 'showed_up', a.showed_up))
        from public.attendance_checks a where a.hit_id = h.id and a.user_id = p_viewer
      ), '[]'::jsonb),
      'relationships', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', x.uid, 'relationship', public.relationship_to(p_viewer, x.uid)))
        from (
          select h.host_id as uid
          union
          select hp.user_id from public.hit_players hp where hp.hit_id = h.id and hp.left_at is null
        ) x
        where p_viewer is not null and x.uid <> p_viewer
      ), '[]'::jsonb)
    )
  )
  from public.hits h where h.id = p_hit;
$$;

create or replace function public.get_inbox() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  return coalesce((
    select jsonb_agg(public.chat_json(c.id, v_user) order by coalesce(c.last_message_at, c.created_at) desc)
    from (
      select c.* from public.chats c
      join public.chat_members me on me.chat_id = c.id and me.user_id = v_user and (me.left_at is null or c.type <> 'dm')
      where not (c.type = 'dm' and exists (
        select 1 from public.chat_members o where o.chat_id = c.id and o.user_id <> v_user and public.is_blocked_either(v_user, o.user_id)))
        and not (c.type = 'hit' and exists (
          select 1 from public.hits h where h.id = c.hit_id and h.status in ('played', 'cancelled', 'expired')
            and public.hit_archive_at(h.starts_at, h.duration_min, h.court_id) < now() - interval '1 day'))
      order by coalesce(c.last_message_at, c.created_at) desc limit 100
    ) c
  ), '[]'::jsonb);
end $$;

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
          and public.hit_archive_at(h.starts_at, h.duration_min, h.court_id) > v_now
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
        where hp.user_id = v_user and hp.left_at is null and (h.status in ('played', 'cancelled', 'expired') or public.hit_archive_at(h.starts_at, h.duration_min, h.court_id) <= v_now)
        order by h.starts_at desc limit 50
      ) x
    ), '[]'::jsonb)
  );
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
           where status = 'confirmed' and public.hit_archive_at(starts_at, duration_min, court_id) < now() returning id loop
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

create or replace function public.has_overlapping_hit(p_user uuid, p_start timestamptz, p_minutes integer, p_except uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h
    where h.status in ('open', 'confirmed') and h.id is distinct from p_except
      and public.is_hit_member(h.id, p_user)
      and case when p_minutes is null or h.duration_min is null then h.starts_at = p_start
          else h.starts_at < p_start + make_interval(mins => p_minutes)
            and h.starts_at + make_interval(mins => h.duration_min) > p_start end
  );
$$;

create or replace function public.attendance_open(p_hit uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select h.status = 'played' and public.hit_archive_at(h.starts_at, h.duration_min, h.court_id) > now() - interval '3 days'
  from public.hits h where h.id = p_hit;
$$;

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
  else
    -- A host may fill unknown facts, but cannot overwrite another court's recorded details.
    update public.courts set apple_place_id = coalesce(apple_place_id, p_apple_place_id),
      surface = coalesce(surface, p_surface), lights = coalesce(lights, p_lights) where id = v_id;
  end if;
  return public.court_json(v_id);
end $$;
