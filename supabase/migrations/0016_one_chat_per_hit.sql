-- A hit no longer opens a chat of its own when a natural one exists.
--
--   two players           -> their direct message (created if needed), the hit card pinned on top
--   born from a group     -> that group chat, as long as every player in the hit is a member
--   three or more others  -> a hit chat of its own, titled after the hit, never after a person
--
-- A DM-hosted hit that gains a third player moves to a hit chat of its own at that moment. Two
-- players who share a live hit may message in their DM without being friends. Hit chats whose
-- hit is over leave the inbox a day later; the thread stays reachable from the hit.
--
-- Also here, each a design gap found in review: pending requesters hear when a hit is cancelled or
-- fills; a declined player can't ask the same hit again; a player can't be in two hits at once;
-- blocking takes the two players out of each other's upcoming hits; the day-after answer closes
-- after three days.

-- Helpers ----------------------------------------------------------------------------------

create or replace function public.hit_chat_label(p_hit uuid) returns text
language sql stable security definer set search_path = public as $$
  select initcap(h.format::text) || ' · ' || public.time_label(h.starts_at) || ' · ' || c.name
  from public.hits h join public.courts c on c.id = h.court_id where h.id = p_hit;
$$;

-- Two players in the same hit that is upcoming, or played within the last day.
create or replace function public.shares_live_hit(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h
    where (h.status in ('open', 'confirmed') or (h.status = 'played' and h.starts_at > now() - interval '1 day'))
      and public.is_hit_member(h.id, p_a) and public.is_hit_member(h.id, p_b)
  );
$$;

-- Does p_user have a live hit overlapping [p_start, p_start + p_minutes)? p_except leaves one hit out.
create or replace function public.has_overlapping_hit(p_user uuid, p_start timestamptz, p_minutes integer, p_except uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h
    where h.status in ('open', 'confirmed') and h.id is distinct from p_except
      and public.is_hit_member(h.id, p_user)
      and h.starts_at < p_start + make_interval(mins => p_minutes)
      and h.starts_at + make_interval(mins => h.duration_min) > p_start
  );
$$;

-- The chat a hit lives in, chosen (and if need be moved) from who is in it right now.
create or replace function public.ensure_hit_chat(p_hit uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare h public.hits; c public.chats; v_chat uuid; v_members uuid[]; v_other uuid; m uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  select array_agg(user_id) into v_members from (
    select h.host_id as user_id
    union select hp.user_id from public.hit_players hp where hp.hit_id = p_hit and hp.role = 'player' and hp.left_at is null
  ) x;

  if h.chat_id is not null then
    select * into c from public.chats where id = h.chat_id;
    -- A DM or group carrying this hit keeps it while everyone in the hit is in that chat.
    if c.type = 'hit' or not exists (
      select 1 from unnest(v_members) u where not public.is_chat_member(c.id, u)
    ) then
      return h.chat_id;
    end if;
    -- Someone joined who isn't in that chat: the hit gets a chat of its own, and the old thread says so.
    insert into public.chats (type, name, hit_id, created_by) values ('hit', public.hit_chat_label(p_hit), p_hit, h.host_id) returning id into v_chat;
    foreach m in array v_members loop
      insert into public.chat_members (chat_id, user_id) values (v_chat, m) on conflict (chat_id, user_id) do update set left_at = null;
    end loop;
    update public.hits set chat_id = v_chat where id = p_hit;
    perform public.system_message(c.id, 'The hit moved to its own chat: ' || public.hit_chat_label(p_hit),
      jsonb_build_object('event', 'hit_moved', 'hit_id', p_hit, 'chat_id', v_chat));
    return v_chat;
  end if;

  -- Born from a group, and everyone in it is in that group: the group is the hit's chat.
  select i.chat_id into v_chat from public.hit_invites i join public.chats gc on gc.id = i.chat_id
  where i.hit_id = p_hit and gc.type = 'group'
    and not exists (select 1 from unnest(v_members) u where not public.is_chat_member(gc.id, u))
  order by i.created_at limit 1;
  if v_chat is not null then
    update public.hits set chat_id = v_chat where id = p_hit;
    return v_chat;
  end if;

  -- Two people: their direct message.
  if cardinality(v_members) = 2 then
    select u into v_other from unnest(v_members) u where u <> h.host_id;
    v_chat := public.ensure_dm_chat(h.host_id, v_other);
    update public.hits set chat_id = v_chat where id = p_hit;
    return v_chat;
  end if;

  insert into public.chats (type, name, hit_id, created_by) values ('hit', public.hit_chat_label(p_hit), p_hit, h.host_id) returning id into v_chat;
  foreach m in array v_members loop
    insert into public.chat_members (chat_id, user_id) values (v_chat, m) on conflict (chat_id, user_id) do update set left_at = null;
  end loop;
  update public.hits set chat_id = v_chat where id = p_hit;
  return v_chat;
end $$;

-- Reads ------------------------------------------------------------------------------------

create or replace function public.chat_display_name(p_chat uuid, p_viewer uuid) returns text
language sql stable security definer set search_path = public as $$
  select case c.type
    when 'group' then c.name
    when 'dm' then (select public.display_name(m.user_id) from public.chat_members m where m.chat_id = c.id and m.user_id <> p_viewer limit 1)
    when 'hit' then coalesce(c.name, public.hit_chat_label(c.hit_id), 'Hit chat')
    end
  from public.chats c where c.id = p_chat;
$$;

-- The hit a thread shows on top: the next live one held in this chat, else the one the chat was made for.
create or replace function public.chat_pinned_hit(p_chat uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select h.id from public.hits h
     where h.chat_id = p_chat and h.status in ('open', 'confirmed') and h.starts_at > now() - interval '1 day'
     order by h.starts_at limit 1),
    (select c.hit_id from public.chats c where c.id = p_chat));
$$;

create or replace function public.chat_json(p_chat uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'type', c.type, 'name', public.chat_display_name(c.id, p_viewer), 'hit_id', public.chat_pinned_hit(c.id),
    'members', (select jsonb_agg(public.player_card(m.user_id) order by m.joined_at)
                from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'member_count', (select count(*) from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'last_message_at', c.last_message_at,
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
        and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id)))),
    'muted', me.muted,
    'friendship', case when c.type = 'dm' then public.relationship_to(p_viewer,
      (select m.user_id from public.chat_members m where m.chat_id = c.id and m.user_id <> p_viewer limit 1)) end,
    'hit', case when public.chat_pinned_hit(c.id) is null then null else public.hit_json(public.chat_pinned_hit(c.id), p_viewer) end
  )
  from public.chats c
  join public.chat_members me on me.chat_id = c.id and me.user_id = p_viewer
  left join lateral (
    select m.id, m.type, m.sender_id, m.body from public.messages m
    where m.id = c.last_message_id and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id))
    union all
    (select m.id, m.type, m.sender_id, m.body from public.messages m
     where m.chat_id = c.id and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id))
     order by m.created_at desc, m.id desc limit 1)
    limit 1
  ) lm on true
  where c.id = p_chat;
$$;

-- The People tab. Blocked DMs stay out; a hit chat leaves a day after its hit is over.
create or replace function public.get_inbox() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  return coalesce((
    select jsonb_agg(public.chat_json(c.id, v_user) order by coalesce(c.last_message_at, c.created_at) desc)
    from (
      select c.* from public.chats c
      join public.chat_members me on me.chat_id = c.id and me.user_id = v_user and me.left_at is null
      where not (c.type = 'dm' and exists (
        select 1 from public.chat_members o where o.chat_id = c.id and o.user_id <> v_user and public.is_blocked_either(v_user, o.user_id)))
        and not (c.type = 'hit' and exists (
          select 1 from public.hits h where h.id = c.hit_id and h.status in ('played', 'cancelled', 'expired')
            and h.starts_at + make_interval(mins => h.duration_min) < now() - interval '1 day'))
      order by coalesce(c.last_message_at, c.created_at) desc limit 100
    ) c
  ), '[]'::jsonb);
end $$;

-- Writes -----------------------------------------------------------------------------------

create or replace function public.send_message(p_chat uuid, p_client_id uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); c public.chats; v_other uuid; v_id uuid; v_body text := btrim(coalesce(p_body, '')); m record;
begin
  select id into v_id from public.messages where chat_id = p_chat and client_id = p_client_id and sender_id = v_user;
  if v_id is not null then return public.message_json(v_id); end if;

  select * into c from public.chats where id = p_chat;
  if not found or not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  if v_body = '' then raise exception 'empty_message'; end if;
  if length(v_body) > 2000 then raise exception 'message_too_long'; end if;
  if c.type = 'dm' then
    select user_id into v_other from public.chat_members where chat_id = p_chat and user_id <> v_user limit 1;
    if public.is_blocked_either(v_user, v_other) then raise exception 'player_unavailable'; end if;
    -- Friends, or two players with a hit together: a DM carries that hit's chat.
    if not public.is_friend(v_user, v_other) and not public.shares_live_hit(v_user, v_other) then raise exception 'not_friends'; end if;
  end if;
  perform public.filter_text(v_body);
  perform public.check_rate_limit('send_message', 30, interval '1 minute');

  begin
    v_id := public.post_message(p_chat, v_user, 'text', v_body, '{}'::jsonb, p_client_id);
  exception when unique_violation then
    select id into v_id from public.messages where chat_id = p_chat and client_id = p_client_id and sender_id = v_user;
    if v_id is null then raise; end if;
    return public.message_json(v_id);
  end;
  update public.chat_members set last_read_at = now() where chat_id = p_chat and user_id = v_user;

  for m in select cm.user_id from public.chat_members cm
           where cm.chat_id = p_chat and cm.left_at is null and cm.muted = false and cm.user_id <> v_user
             and not public.is_blocked_either(v_user, cm.user_id) loop
    perform public.notify(m.user_id, 'message',
      case when c.type = 'dm' then public.display_name(v_user) else public.chat_display_name(c.id, m.user_id) end,
      case when c.type = 'dm' then left(v_body, 140) else public.display_name(v_user) || ': ' || left(v_body, 140) end,
      'courtly://chat/' || p_chat, 'chat-' || p_chat, jsonb_build_object('chat_id', p_chat, 'message_id', v_id));
  end loop;
  return public.message_json(v_id);
end $$;

-- A joiner leaves before the hit starts. The spot reopens; the host is told. Only a chat made for
-- the hit loses the leaver: a DM or group is theirs regardless.
create or replace function public.leave_hit(p_hit uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_remaining integer;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found then raise exception 'hit_not_found'; end if;
  if h.host_id = v_user then raise exception 'host_cannot_leave'; end if;
  if h.status not in ('open', 'confirmed') then raise exception 'hit_closed'; end if;
  if h.starts_at <= now() then raise exception 'hit_started'; end if;
  update public.hit_players set left_at = now() where hit_id = p_hit and user_id = v_user and left_at is null;
  if not found then raise exception 'not_a_player'; end if;

  select count(*) into v_remaining from public.hit_players where hit_id = p_hit and role = 'player' and left_at is null;
  update public.hits set spots_open = spots_open + 1, status = case when v_remaining = 0 then 'open' else status end
  where id = p_hit;
  update public.chat_members cm set left_at = now() from public.chats c
  where c.id = cm.chat_id and cm.chat_id = h.chat_id and cm.user_id = v_user and c.type = 'hit';

  perform public.system_message(h.chat_id, public.display_name(v_user) || ' left the hit',
    jsonb_build_object('event', 'player_left', 'actor', v_user));
  perform public.notify(h.host_id, 'player_left', 'Courtly',
    public.display_name(v_user) || ' can’t make ' || public.hit_push_label(p_hit) || '. The spot is open again.',
    'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  return public.hit_json(p_hit, v_user);
end $$;

-- Closes a hit. Players and anyone still waiting on an answer are told.
create or replace function public.close_hit(p_hit uuid, p_note text default '', p_actor uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.hits; p record;
begin
  select * into h from public.hits where id = p_hit;
  if not found or h.status not in ('open', 'confirmed') then return; end if;
  update public.hits set status = 'cancelled', cancelled_at = now() where id = p_hit;
  for p in update public.join_requests set status = 'cancelled', responded_at = now()
           where hit_id = p_hit and status = 'pending' returning user_id loop
    perform public.notify(p.user_id, 'request_declined', 'Courtly',
      public.hit_push_label(p_hit) || ' was cancelled before the host could answer you.',
      'courtly://play', 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  end loop;
  update public.hit_invites set status = 'cancelled' where hit_id = p_hit and status = 'open';
  for p in select user_id from public.hit_players where hit_id = p_hit and role = 'player' and left_at is null loop
    perform public.notify(p.user_id, 'hit_cancelled', 'Courtly',
      public.hit_push_label(p_hit) || ' is off.' || case when coalesce(p_note, '') = '' then '' else ' ' || p_note end,
      'courtly://play', 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  end loop;
  if p_actor is not null and h.chat_id is not null then
    perform public.system_message(h.chat_id, public.display_name(p_actor) || ' cancelled the hit',
      jsonb_build_object('event', 'hit_cancelled', 'actor', p_actor));
  end if;
end $$;

create or replace function public.add_player(p_hit uuid, p_user uuid, p_source public.player_source) returns void
language plpgsql security definer set search_path = public as $$
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
  -- One answer per hit: a host who said no isn't asked again.
  if exists (select 1 from public.join_requests where hit_id = p_hit and user_id = v_user and status = 'declined') then
    raise exception 'already_declined';
  end if;
  if public.has_overlapping_hit(v_user, h.starts_at, h.duration_min, p_hit) then raise exception 'overlaps_hit'; end if;
  perform public.check_rate_limit('request_to_join', 30, interval '1 day');

  insert into public.join_requests (hit_id, user_id) values (p_hit, v_user) returning id into v_id;
  perform public.notify(h.host_id, 'join_request', 'Courtly',
    public.display_name(v_user) || ' asked to join your hit, ' || public.hit_push_label(p_hit) || '.',
    'courtly://request/' || v_id, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit, 'request_id', v_id));
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
  if public.has_overlapping_hit(v_user, p_starts_at, p_duration_min) then raise exception 'overlaps_hit'; end if;
  perform public.check_rate_limit('create_hit', 20, interval '1 day');

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

-- Blocking also takes the two players out of each other's upcoming hits.
create or replace function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); r record;
begin
  if p_user = v_user then raise exception 'cannot_block_self'; end if;
  insert into public.blocks (blocker_id, blocked_id) values (v_user, p_user) on conflict do nothing;
  delete from public.friendships where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user);
  update public.join_requests jr set status = 'cancelled', responded_at = now()
  from public.hits h where h.id = jr.hit_id and jr.status = 'pending'
    and ((jr.user_id = p_user and h.host_id = v_user) or (jr.user_id = v_user and h.host_id = p_user));
  update public.hit_invites set status = 'cancelled'
  where status = 'open' and ((created_by = v_user and target_user_id = p_user) or (created_by = p_user and target_user_id = v_user));

  -- Upcoming hits the two share: the one who is only a player leaves it; the spot reopens.
  for r in select h.id as hit_id, h.host_id, h.chat_id,
                  case when h.host_id = v_user then p_user when h.host_id = p_user then v_user else null end as leaver
           from public.hits h
           where h.status in ('open', 'confirmed') and h.starts_at > now()
             and public.is_hit_member(h.id, v_user) and public.is_hit_member(h.id, p_user) loop
    if r.leaver is null then continue; end if;   -- neither hosts: the host decides; nothing here
    update public.hit_players set left_at = now() where hit_id = r.hit_id and user_id = r.leaver and left_at is null;
    if found then
      update public.hits set spots_open = spots_open + 1,
        status = case when exists (select 1 from public.hit_players x where x.hit_id = r.hit_id and x.role = 'player' and x.left_at is null)
                      then status else 'open' end
      where id = r.hit_id;
      update public.chat_members cm set left_at = now() from public.chats c
      where c.id = cm.chat_id and cm.chat_id = r.chat_id and cm.user_id = r.leaver and c.type = 'hit';
      if r.chat_id is not null then
        perform public.system_message(r.chat_id, public.display_name(r.leaver) || ' left the hit',
          jsonb_build_object('event', 'player_left', 'actor', r.leaver));
      end if;
    end if;
  end loop;
end $$;

-- The day-after answer closes three days after the hit, so nobody is nagged for weeks and no
-- absence can be recorded long after the fact.
create or replace function public.attendance_open(p_hit uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select h.status = 'played' and h.starts_at + make_interval(mins => h.duration_min) > now() - interval '3 days'
  from public.hits h where h.id = p_hit;
$$;

create or replace function public.needs_attendance(p_hit uuid, p_viewer uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.attendance_open(p_hit) and exists (
    select 1 from public.hits h
    join public.hit_players o on o.hit_id = h.id and o.user_id <> p_viewer and o.left_at is null
    where h.id = p_hit
      and exists (select 1 from public.hit_players me where me.hit_id = h.id and me.user_id = p_viewer and me.left_at is null)
      and not exists (select 1 from public.attendance_checks a where a.hit_id = h.id and a.user_id = p_viewer and a.about_user_id = o.user_id)
  );
$$;

create or replace function public.submit_attendance(p_hit uuid, p_about uuid, p_showed_up boolean, p_add_friend boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_prev boolean; v_others_no boolean; v_report uuid; v_reporter uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.status <> 'played' then raise exception 'hit_not_played'; end if;
  if not public.attendance_open(p_hit) then raise exception 'attendance_closed'; end if;
  if not public.is_hit_member(p_hit, v_user) or not public.is_hit_member(p_hit, p_about) or p_about = v_user then
    raise exception 'not_a_player';
  end if;

  select showed_up into v_prev from public.attendance_checks where hit_id = p_hit and user_id = v_user and about_user_id = p_about;
  v_others_no := exists (select 1 from public.attendance_checks
                         where hit_id = p_hit and about_user_id = p_about and user_id <> v_user and showed_up = false);
  insert into public.attendance_checks (hit_id, user_id, about_user_id, showed_up) values (p_hit, v_user, p_about, p_showed_up)
  on conflict (hit_id, user_id, about_user_id) do update set showed_up = excluded.showed_up, created_at = now();

  if not p_showed_up and v_prev is distinct from false and not v_others_no then
    update public.profiles set no_shows = no_shows + 1, hits_played = greatest(hits_played - 1, 0) where id = p_about;
    insert into public.reports (reporter_id, reported_id, hit_id, reason, auto) values (v_user, p_about, p_hit, 'no_show', true);
  elsif p_showed_up and v_prev = false and not v_others_no then
    update public.profiles set no_shows = greatest(no_shows - 1, 0), hits_played = hits_played + 1 where id = p_about;
    delete from public.reports where hit_id = p_hit and reported_id = p_about and reason = 'no_show' and auto;
  elsif p_showed_up and v_prev = false and v_others_no then
    update public.reports set reporter_id = (
      select user_id from public.attendance_checks
      where hit_id = p_hit and about_user_id = p_about and user_id <> v_user and showed_up = false
      order by created_at limit 1)
    where hit_id = p_hit and reported_id = p_about and reason = 'no_show' and auto and reporter_id = v_user
    returning id, reporter_id into v_report, v_reporter;
    if v_report is not null then
      delete from public.notifications where user_id = v_reporter and kind = 'report' and collapse_id = 'report-' || v_report::text;
    end if;
  end if;
  if p_add_friend then perform public.add_friend(p_about); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Existing data -------------------------------------------------------------------------------
-- Two-person hit chats fold into the pair's DM, messages and all; the rest take the hit's title.

do $$
declare r record; v_dm uuid; v_other uuid;
begin
  for r in select c.id, h.host_id, h.id as hit_id from public.chats c join public.hits h on h.id = c.hit_id
           where c.type = 'hit'
             and (select count(*) from public.chat_members m where m.chat_id = c.id and m.left_at is null) = 2 loop
    select m.user_id into v_other from public.chat_members m where m.chat_id = r.id and m.user_id <> r.host_id and m.left_at is null;
    if v_other is null then continue; end if;
    v_dm := public.ensure_dm_chat(r.host_id, v_other);
    update public.messages set chat_id = v_dm where chat_id = r.id;
    update public.hit_invites set chat_id = v_dm where chat_id = r.id;
    update public.hits set chat_id = v_dm where chat_id = r.id;
    update public.chat_members dm set last_read_at = greatest(dm.last_read_at, old.last_read_at)
    from public.chat_members old where old.chat_id = r.id and dm.chat_id = v_dm and dm.user_id = old.user_id;
    update public.chats set last_message_id = m.id, last_message_at = m.created_at,
      last_message_preview = case when m.type = 'text' and m.sender_id is not null
        then public.display_name(m.sender_id) || ': ' || left(m.body, 120) else left(m.body, 120) end
    from (select id, created_at, type, sender_id, body from public.messages where chat_id = v_dm order by created_at desc, id desc limit 1) m
    where public.chats.id = v_dm;
    delete from public.chat_members where chat_id = r.id;
    delete from public.chats where id = r.id;
  end loop;
  update public.chats c set name = public.hit_chat_label(c.hit_id) where c.type = 'hit' and c.hit_id is not null and c.name is null;
end $$;

revoke execute on function public.hit_chat_label(uuid) from public, anon, authenticated;
revoke execute on function public.shares_live_hit(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.has_overlapping_hit(uuid, timestamptz, integer, uuid) from public, anon, authenticated;
revoke execute on function public.chat_pinned_hit(uuid) from public, anon, authenticated;
revoke execute on function public.attendance_open(uuid) from public, anon, authenticated;
revoke execute on function public.ensure_hit_chat(uuid) from public, anon, authenticated;
revoke execute on function public.close_hit(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.add_player(uuid, uuid, public.player_source) from public, anon, authenticated;
