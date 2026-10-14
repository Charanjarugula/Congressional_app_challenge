-- Hit lifecycle: create, ask, accept, invite, claim, leave, cancel, attendance.
-- add_player is the only place a spot is consumed, so the spot invariant lives there.

-- Internal helpers ------------------------------------------------------------------

create or replace function public.display_name(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when p.last_name = '' then p.first_name else p.first_name || ' ' || left(p.last_name, 1) || '.' end
  from public.profiles p where p.id = p_user;
$$;

-- "Thu 6:30 PM" in the county's time zone.
create or replace function public.time_label(p_at timestamptz) returns text
language sql immutable as $$
  select to_char(p_at at time zone 'America/New_York', 'Dy FMHH12:MI AM');
$$;

create or replace function public.notify(
  p_user uuid, p_kind public.notification_kind, p_title text, p_body text,
  p_deep_link text default null, p_collapse_id text default null, p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  insert into public.notifications (user_id, kind, title, body, deep_link, collapse_id, data)
  values (p_user, p_kind, p_title, p_body, p_deep_link, p_collapse_id, coalesce(p_data, '{}'::jsonb));
end $$;

-- Inserts a message and refreshes the chat's inbox fields. Returns the message id.
create or replace function public.post_message(
  p_chat uuid, p_sender uuid, p_type public.message_type, p_body text, p_payload jsonb default '{}'::jsonb, p_client_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_preview text;
begin
  insert into public.messages (chat_id, sender_id, type, body, payload, client_id)
  values (p_chat, p_sender, p_type, p_body, coalesce(p_payload, '{}'::jsonb), p_client_id)
  returning id into v_id;
  v_preview := case
    when p_type = 'text' and p_sender is not null then public.display_name(p_sender) || ': ' || left(p_body, 120)
    else left(p_body, 120) end;
  update public.chats set last_message_id = v_id, last_message_at = now(), last_message_preview = v_preview where id = p_chat;
  return v_id;
end $$;

create or replace function public.system_message(p_chat uuid, p_body text, p_payload jsonb) returns uuid
language sql security definer set search_path = public as $$
  select public.post_message(p_chat, null, 'system', p_body, p_payload, null);
$$;

create or replace function public.ensure_hit_chat(p_hit uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare h public.hits; v_chat uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if h.chat_id is not null then return h.chat_id; end if;
  insert into public.chats (type, hit_id, created_by) values ('hit', p_hit, h.host_id) returning id into v_chat;
  insert into public.chat_members (chat_id, user_id) values (v_chat, h.host_id);
  update public.hits set chat_id = v_chat where id = p_hit;
  return v_chat;
end $$;

-- Consumes one spot under a row lock. Closes invites and expires other asks when the hit fills.
create or replace function public.add_player(p_hit uuid, p_user uuid, p_source public.player_source) returns void
language plpgsql security definer set search_path = public as $$
declare h public.hits; v_chat uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found then raise exception 'hit_not_found'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'hit_full'; end if;
  if h.host_id = p_user then raise exception 'already_in'; end if;
  if exists (select 1 from public.hit_players where hit_id = p_hit and user_id = p_user and left_at is null) then
    raise exception 'already_in';
  end if;

  insert into public.hit_players (hit_id, user_id, role, source) values (p_hit, p_user, 'player', p_source)
  on conflict (hit_id, user_id) do update set left_at = null, joined_at = now(), source = excluded.source;

  update public.hits set spots_open = spots_open - 1, status = 'confirmed' where id = p_hit returning * into h;

  v_chat := public.ensure_hit_chat(p_hit);
  insert into public.chat_members (chat_id, user_id) values (v_chat, p_user)
  on conflict (chat_id, user_id) do update set left_at = null;

  if h.spots_open = 0 then
    update public.hit_invites set status = 'filled' where hit_id = p_hit and status = 'open';
    update public.join_requests set status = 'expired', responded_at = now() where hit_id = p_hit and status = 'pending';
  end if;
end $$;

-- The one shape every hit screen reads.
create or replace function public.hit_json(p_hit uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', h.id,
    'host', public.player_card(h.host_id),
    'court', public.court_json(h.court_id),
    'starts_at', h.starts_at,
    'duration_min', h.duration_min,
    'format', h.format,
    'spots_total', h.spots_total,
    'spots_open', h.spots_open,
    'visibility', h.visibility,
    'status', h.status,
    'chat_id', h.chat_id,
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
      )
    )
  )
  from public.hits h where h.id = p_hit;
$$;

create or replace function public.invite_json(p_invite uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', i.id, 'hit_id', i.hit_id, 'chat_id', i.chat_id, 'message_id', i.message_id,
    'created_by', public.player_card(i.created_by), 'target_user_id', i.target_user_id,
    'spots', i.spots, 'claimed', i.claimed, 'expires_at', i.expires_at, 'status', i.status,
    'hit', public.hit_json(i.hit_id, p_viewer)
  )
  from public.hit_invites i where i.id = p_invite;
$$;

create or replace function public.hit_push_label(p_hit uuid) returns text
language sql stable security definer set search_path = public as $$
  select public.time_label(h.starts_at) || ' at ' || c.name
  from public.hits h join public.courts c on c.id = h.court_id where h.id = p_hit;
$$;

-- Public functions --------------------------------------------------------------------

create or replace function public.get_hit(p_hit uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if not public.can_see_hit(p_hit, v_user) then raise exception 'hit_not_found'; end if;
  return public.hit_json(p_hit, v_user);
end $$;

create or replace function public.create_hit(
  p_court_id uuid, p_starts_at timestamptz, p_duration_min integer, p_format public.play_format, p_spots integer,
  p_visibility public.hit_visibility default 'anyone', p_invite_chat_id uuid default null, p_invite_expires_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); v_visibility public.hit_visibility := p_visibility; v_id uuid;
begin
  if p_starts_at <= now() + interval '15 minutes' then raise exception 'starts_in_past'; end if;
  if p_starts_at > now() + interval '30 days' then raise exception 'too_far_ahead'; end if;
  if p_spots not between 1 and 7 then raise exception 'invalid_spots'; end if;
  if p_duration_min not in (60, 90, 120) then raise exception 'invalid_duration'; end if;
  if not exists (select 1 from public.courts where id = p_court_id and hidden = false) then raise exception 'court_not_found'; end if;
  if p_invite_chat_id is not null and not public.is_chat_member(p_invite_chat_id, v_user) then raise exception 'not_a_member'; end if;
  perform public.check_rate_limit('create_hit', 20, interval '1 day');

  -- A player who hides hits from strangers cannot post one visible to anyone.
  if v_visibility = 'anyone' and not public.host_allows_anyone(v_user) then v_visibility := 'friends'; end if;

  insert into public.hits (host_id, court_id, starts_at, duration_min, format, spots_total, spots_open, visibility)
  values (v_user, p_court_id, p_starts_at, p_duration_min, p_format, p_spots, p_spots, v_visibility)
  returning id into v_id;
  insert into public.hit_players (hit_id, user_id, role, source) values (v_id, v_user, 'host', 'host');

  if p_invite_chat_id is not null then
    perform public.send_hit_invite(v_id, p_invite_chat_id, null, p_invite_expires_at);
  end if;
  return public.hit_json(v_id, v_user);
end $$;

create or replace function public.request_to_join(p_hit uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_id uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or not public.can_see_hit(p_hit, v_user) then raise exception 'hit_not_found'; end if;
  if h.host_id = v_user or public.is_hit_member(p_hit, v_user) then raise exception 'already_in'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'hit_full'; end if;
  if public.is_blocked_either(v_user, h.host_id) then raise exception 'hit_not_found'; end if;
  if exists (select 1 from public.join_requests where hit_id = p_hit and user_id = v_user and status = 'pending') then
    raise exception 'already_requested';
  end if;
  perform public.check_rate_limit('request_to_join', 30, interval '1 day');

  insert into public.join_requests (hit_id, user_id) values (p_hit, v_user) returning id into v_id;
  perform public.notify(h.host_id, 'join_request', 'Courtly',
    public.display_name(v_user) || ' asked to join your hit, ' || public.hit_push_label(p_hit) || '.',
    'courtly://request/' || v_id, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit, 'request_id', v_id));
  return public.hit_json(p_hit, v_user);
end $$;

create or replace function public.respond_to_request(p_request uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); r public.join_requests; h public.hits;
begin
  select * into r from public.join_requests where id = p_request for update;
  if not found then raise exception 'request_not_found'; end if;
  select * into h from public.hits where id = r.hit_id for update;
  if h.host_id <> v_user then raise exception 'not_host'; end if;
  if r.status <> 'pending' then raise exception 'request_closed'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;

  if p_accept then
    update public.join_requests set status = 'accepted', responded_at = now() where id = p_request;
    perform public.add_player(h.id, r.user_id, 'ask');
    select * into h from public.hits where id = r.hit_id;
    perform public.system_message(h.chat_id,
      public.display_name(v_user) || ' accepted ' || public.display_name(r.user_id) || '’s request',
      jsonb_build_object('event', 'request_accepted', 'actor', v_user, 'subject', r.user_id));
    perform public.notify(r.user_id, 'request_accepted', 'Courtly',
      public.display_name(v_user) || ' accepted you · ' || public.hit_push_label(h.id),
      'courtly://hit/' || h.id, 'hit-' || h.id, jsonb_build_object('hit_id', h.id, 'chat_id', h.chat_id));
  else
    update public.join_requests set status = 'declined', responded_at = now() where id = p_request;
    perform public.notify(r.user_id, 'request_declined', 'Courtly',
      public.display_name(v_user) || ' couldn’t fit you in this time', 'courtly://play', 'hit-' || h.id,
      jsonb_build_object('hit_id', h.id));
  end if;
  return public.hit_json(h.id, v_user);
end $$;

create or replace function public.cancel_request(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded();
begin
  update public.join_requests set status = 'cancelled', responded_at = now()
  where id = p_request and user_id = v_user and status = 'pending';
  if not found then raise exception 'request_not_found'; end if;
end $$;

create or replace function public.mark_request_seen(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.join_requests set seen_by_requester_at = now()
  where id = p_request and user_id = auth.uid() and seen_by_requester_at is null;
end $$;

-- Host offers the open spots to a friend (their DM) or a group chat. No approval: first claim wins.
create or replace function public.send_hit_invite(
  p_hit uuid, p_chat uuid, p_target_user uuid default null, p_expires_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.assert_onboarded(); h public.hits; v_invite uuid; v_message uuid; v_expires timestamptz;
  v_evening_before timestamptz; v_body text; m record;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.host_id <> v_user then raise exception 'not_host'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'hit_full'; end if;
  if not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  if p_target_user is not null then
    if not public.is_chat_member(p_chat, p_target_user) then raise exception 'not_a_member'; end if;
    if public.is_blocked_either(v_user, p_target_user) then raise exception 'player_unavailable'; end if;
    if public.is_hit_member(p_hit, p_target_user) then raise exception 'already_in'; end if;
  end if;

  -- Default expiry: 8 PM the evening before, or two hours before start, whichever is sooner; never in the past.
  v_evening_before := (date_trunc('day', h.starts_at at time zone 'America/New_York') - interval '1 day' + interval '20 hours')
                      at time zone 'America/New_York';
  v_expires := coalesce(p_expires_at, least(h.starts_at - interval '2 hours', v_evening_before));
  if v_expires <= now() then v_expires := least(h.starts_at - interval '30 minutes', now() + interval '12 hours'); end if;
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

-- The atomic "I'm in". Locks the hit first, then the invite, the same order every other writer uses.
create or replace function public.claim_invite(p_invite uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); i public.hit_invites; h public.hits;
begin
  select hh.* into h from public.hits hh where hh.id = (select hit_id from public.hit_invites where id = p_invite) for update;
  if not found then raise exception 'invite_not_found'; end if;
  select * into i from public.hit_invites where id = p_invite for update;
  if i.status <> 'open' or i.expires_at < now() then raise exception 'invite_closed'; end if;
  if i.target_user_id is not null and i.target_user_id <> v_user then raise exception 'not_for_you'; end if;
  if i.target_user_id is null and not public.is_chat_member(i.chat_id, v_user) then raise exception 'not_a_member'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'spot_taken'; end if;
  if h.host_id = v_user or public.is_hit_member(h.id, v_user) then raise exception 'already_in'; end if;
  if public.is_blocked_either(v_user, h.host_id) then raise exception 'player_unavailable'; end if;

  perform public.add_player(h.id, v_user, 'invite');
  update public.hit_invites set claimed = claimed + 1,
    status = case when claimed + 1 >= spots then 'filled' else status end
  where id = p_invite;

  select * into h from public.hits where id = h.id;
  perform public.system_message(h.chat_id, public.display_name(v_user) || ' is in',
    jsonb_build_object('event', 'player_joined', 'actor', v_user));
  perform public.notify(h.host_id, 'player_joined', 'Courtly',
    public.display_name(v_user) || ' is in for ' || public.hit_push_label(h.id),
    'courtly://hit/' || h.id, 'hit-' || h.id, jsonb_build_object('hit_id', h.id));
  return public.hit_json(h.id, v_user);
end $$;

create or replace function public.decline_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded();
begin
  update public.hit_invites set status = 'cancelled' where id = p_invite and target_user_id = v_user and status = 'open';
  if not found then raise exception 'invite_not_found'; end if;
end $$;

-- A joiner leaves before the hit starts. The spot reopens; the host is told.
create or replace function public.leave_hit(p_hit uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_remaining integer;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found then raise exception 'hit_not_found'; end if;
  if h.host_id = v_user then raise exception 'host_cannot_leave'; end if;
  if h.starts_at <= now() then raise exception 'hit_started'; end if;
  update public.hit_players set left_at = now() where hit_id = p_hit and user_id = v_user and left_at is null;
  if not found then raise exception 'not_a_player'; end if;

  select count(*) into v_remaining from public.hit_players where hit_id = p_hit and role = 'player' and left_at is null;
  update public.hits set spots_open = spots_open + 1, status = case when v_remaining = 0 then 'open' else status end
  where id = p_hit;
  update public.chat_members set left_at = now() where chat_id = h.chat_id and user_id = v_user;

  perform public.system_message(h.chat_id, public.display_name(v_user) || ' left the hit',
    jsonb_build_object('event', 'player_left', 'actor', v_user));
  perform public.notify(h.host_id, 'player_left', 'Courtly',
    public.display_name(v_user) || ' can’t make ' || public.hit_push_label(p_hit) || '. The spot is open again.',
    'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  return public.hit_json(p_hit, v_user);
end $$;

create or replace function public.cancel_hit(p_hit uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; p record;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.host_id <> v_user then raise exception 'not_host'; end if;
  if h.status not in ('open', 'confirmed') then raise exception 'hit_closed'; end if;

  update public.hits set status = 'cancelled', cancelled_at = now() where id = p_hit;
  update public.join_requests set status = 'cancelled', responded_at = now() where hit_id = p_hit and status = 'pending';
  update public.hit_invites set status = 'cancelled' where hit_id = p_hit and status = 'open';

  for p in select user_id from public.hit_players where hit_id = p_hit and role = 'player' and left_at is null loop
    perform public.notify(p.user_id, 'hit_cancelled', 'Courtly',
      public.hit_push_label(p_hit) || ' is off. ' || public.display_name(v_user) || ' cancelled.',
      'courtly://play', 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  end loop;
  if h.chat_id is not null then
    perform public.system_message(h.chat_id, public.display_name(v_user) || ' cancelled the hit',
      jsonb_build_object('event', 'hit_cancelled', 'actor', v_user));
  end if;
  return public.hit_json(p_hit, v_user);
end $$;

-- Day-after answer. Counters change once per (hit, absent player), on the first "No".
create or replace function public.submit_attendance(p_hit uuid, p_about uuid, p_showed_up boolean, p_add_friend boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_first_no boolean;
begin
  select * into h from public.hits where id = p_hit;
  if not found or h.status <> 'played' then raise exception 'hit_not_played'; end if;
  if not public.is_hit_member(p_hit, v_user) or not public.is_hit_member(p_hit, p_about) or p_about = v_user then
    raise exception 'not_a_player';
  end if;

  v_first_no := not exists (select 1 from public.attendance_checks where hit_id = p_hit and about_user_id = p_about and showed_up = false);
  insert into public.attendance_checks (hit_id, user_id, about_user_id, showed_up) values (p_hit, v_user, p_about, p_showed_up)
  on conflict (hit_id, user_id, about_user_id) do update set showed_up = excluded.showed_up, created_at = now();

  if not p_showed_up and v_first_no then
    update public.profiles set no_shows = no_shows + 1, hits_played = greatest(hits_played - 1, 0) where id = p_about;
    insert into public.reports (reporter_id, reported_id, hit_id, reason, auto) values (v_user, p_about, p_hit, 'no_show', true);
  end if;
  if p_add_friend then perform public.add_friend(p_about); end if;
  return jsonb_build_object('ok', true);
end $$;
