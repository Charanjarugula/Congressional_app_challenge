-- Review findings on the backend. Suspended or deleted players read nothing over the API and the policy
-- helpers only answer for the caller; the raw chats row (whose preview copies text a block should hide) is
-- not readable; deletion locks each hit before releasing a spot, keeps the day-after answers it gave, and
-- treats the underage path as the full one for an account that finished onboarding; a withdrawn "No" hands
-- its report to a player still saying it; a suspended player can't be accepted, keeps nothing pending and
-- can't refresh their sign-in; two first adds landing together add back; a retried send can't trip the
-- client-id index; a late commit can't move an inbox preview backwards; preview and type describe the same
-- message; nearby courts rank played ones first before the cut; free_this_week caps at six.

-- Policies answer for the caller only ---------------------------------------------------------------
-- The two-player helpers stay for the functions (which run as their owner); the app role gets wrappers
-- that take the caller from the session, so nobody can ask about two other players.

create or replace function public.viewer_is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active_user(auth.uid());
$$;

create or replace function public.viewer_can_see_hit(p_hit uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active_user(auth.uid()) and public.can_see_hit(p_hit, auth.uid());
$$;

create or replace function public.viewer_is_hit_host(p_hit uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active_user(auth.uid()) and public.is_hit_host(p_hit, auth.uid());
$$;

create or replace function public.viewer_is_chat_member(p_chat uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active_user(auth.uid()) and public.is_chat_member(p_chat, auth.uid());
$$;

create or replace function public.viewer_is_blocked_with(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_blocked_either(auth.uid(), p_user);
$$;

alter policy hits_select on public.hits using (public.viewer_can_see_hit(id));
alter policy hit_players_select on public.hit_players using (public.viewer_can_see_hit(hit_id));
alter policy join_requests_select on public.join_requests
  using (public.viewer_is_active() and (user_id = auth.uid() or public.viewer_is_hit_host(hit_id)));
alter policy hit_invites_select on public.hit_invites
  using (public.viewer_is_active() and (target_user_id = auth.uid() or public.viewer_is_chat_member(chat_id) or public.viewer_is_hit_host(hit_id)));
alter policy friendships_select on public.friendships using (public.viewer_is_active() and auth.uid() in (user_a, user_b));
alter policy blocks_select on public.blocks using (public.viewer_is_active() and blocker_id = auth.uid());
alter policy chats_select on public.chats using (public.viewer_is_chat_member(id));
alter policy chat_members_select on public.chat_members using (public.viewer_is_chat_member(chat_id));
alter policy messages_select on public.messages
  using (public.viewer_is_chat_member(chat_id) and (sender_id is null or not public.viewer_is_blocked_with(sender_id)));
alter policy notifications_select on public.notifications using (public.viewer_is_active() and user_id = auth.uid());
alter policy notifications_update on public.notifications
  using (public.viewer_is_active() and user_id = auth.uid()) with check (public.viewer_is_active() and user_id = auth.uid());
alter policy attendance_select on public.attendance_checks using (public.viewer_is_active() and user_id = auth.uid());

grant execute on function
  public.viewer_is_active(), public.viewer_can_see_hit(uuid), public.viewer_is_hit_host(uuid),
  public.viewer_is_chat_member(uuid), public.viewer_is_blocked_with(uuid)
to authenticated;
revoke execute on function
  public.can_see_hit(uuid, uuid), public.is_hit_host(uuid, uuid), public.is_chat_member(uuid, uuid),
  public.is_blocked_either(uuid, uuid), public.is_active_user(uuid)
from authenticated;

-- The view runs its predicates as the caller, so it takes the wrappers too.
create or replace view public.player_cards with (security_invoker = false) as
  select p.id, p.first_name, left(p.last_name, 1) as last_initial, p.photo_path, p.level, p.formats,
         p.area_label, p.hits_played, p.availability_mask, p.busy_mask_week
  from public.profiles p
  where auth.uid() is not null
    and public.viewer_is_active()
    and p.onboarding_completed_at is not null
    and p.suspended_at is null and p.deleted_at is null
    and not public.viewer_is_blocked_with(p.id);

-- The chats row carries the last message's text, whoever sent it. The app reads chats through chat_json
-- (which hides a blocked player's) and listens to messages, hits and join requests; it never reads this table.
revoke select on public.chats from authenticated;

-- Messages ------------------------------------------------------------------------------------------

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
  -- A send that started earlier can commit later; it must not move the inbox entry backwards.
  update public.chats set last_message_id = v_id, last_message_at = now(), last_message_preview = v_preview
  where id = p_chat and (last_message_at is null or last_message_at <= now());
  return v_id;
end $$;

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
    if not public.is_friend(v_user, v_other) then raise exception 'not_friends'; end if;
  end if;
  perform public.filter_text(v_body);
  perform public.check_rate_limit('send_message', 30, interval '1 minute');

  begin
    v_id := public.post_message(p_chat, v_user, 'text', v_body, '{}'::jsonb, p_client_id);
  exception when unique_violation then
    -- The same send, retried while the first copy was still committing: hand back what that one saved.
    select id into v_id from public.messages where chat_id = p_chat and client_id = p_client_id and sender_id = v_user;
    if v_id is null then raise; end if;
    return public.message_json(v_id);
  end;
  update public.chat_members set last_read_at = now() where chat_id = p_chat and user_id = v_user;

  for m in select cm.user_id from public.chat_members cm
           where cm.chat_id = p_chat and cm.left_at is null and cm.muted = false and cm.user_id <> v_user
             and not public.is_blocked_either(v_user, cm.user_id) loop
    perform public.notify(m.user_id, 'message',
      case when c.type = 'group' then c.name else public.display_name(v_user) end,
      case when c.type = 'group' then public.display_name(v_user) || ': ' || left(v_body, 140) else left(v_body, 140) end,
      'courtly://chat/' || p_chat, 'chat-' || p_chat, jsonb_build_object('chat_id', p_chat, 'message_id', v_id));
  end loop;
  return public.message_json(v_id);
end $$;

create or replace function public.chat_json(p_chat uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'type', c.type, 'name', public.chat_display_name(c.id, p_viewer), 'hit_id', c.hit_id,
    'members', (select jsonb_agg(public.player_card(m.user_id) order by m.joined_at)
                from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'member_count', (select count(*) from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'last_message_at', c.last_message_at,
    -- Both describe the newest message this viewer may see, so a blocked player's last word never shows
    -- and the type always belongs to the preview.
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
    'hit', case when c.hit_id is null then null else public.hit_json(c.hit_id, p_viewer) end
  )
  from public.chats c
  join public.chat_members me on me.chat_id = c.id and me.user_id = p_viewer
  left join lateral (
    -- The recorded last message when the viewer may see it; otherwise the newest one they may.
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

-- Courts and the feed --------------------------------------------------------------------------------

-- Courts near the caller: played-at first, then by distance. The ranking happens before the cut, so a
-- court played further away still comes first.
create or replace function public.get_nearby_courts(p_limit integer default 30) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  with me as (select home_point from public.profiles where id = public.assert_signed_in()),
  ranked as (
    select c.id, extensions.st_distance(c.point, me.home_point) as metres,
           (select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
            where h.court_id = c.id and hp.user_id = auth.uid() and h.status = 'played') as played_count
    from public.courts c, me
    where c.hidden = false and me.home_point is not null
    order by played_count desc, metres limit p_limit
  )
  select coalesce(jsonb_agg(public.court_json(r.id) || jsonb_build_object(
           'miles', round((r.metres / 1609.344)::numeric, 1), 'played_count', r.played_count)
         order by r.played_count desc, r.metres), '[]'::jsonb)
  from ranked r;
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
      select jsonb_agg(public.player_card(free.other))
      from (
        select f.other
        from (
          select case when fr.user_a = v_user then fr.user_b else fr.user_a end as other
          from public.friendships fr where fr.status = 'accepted' and v_user in (fr.user_a, fr.user_b)
        ) f
        join public.profiles p on p.id = f.other
        where public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
          and (p.availability_mask & ~coalesce(p.busy_mask_week, 0) & public.remaining_week_mask()) <> 0
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

-- Hits ----------------------------------------------------------------------------------------------

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
  -- A request or an invite can outlive a suspension by moments; the player it names must still be active.
  if not public.is_active_user(p_user) then raise exception 'player_unavailable'; end if;

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

create or replace function public.submit_attendance(p_hit uuid, p_about uuid, p_showed_up boolean, p_add_friend boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_prev boolean; v_others_no boolean;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.status <> 'played' then raise exception 'hit_not_played'; end if;
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
    -- Someone else still says "No", so the absence stands; the automatic report moves to them instead
    -- of staying in the name of a player who took their answer back.
    update public.reports set reporter_id = (
      select user_id from public.attendance_checks
      where hit_id = p_hit and about_user_id = p_about and user_id <> v_user and showed_up = false
      order by created_at limit 1)
    where hit_id = p_hit and reported_id = p_about and reason = 'no_show' and auto and reporter_id = v_user;
  end if;
  if p_add_friend then perform public.add_friend(p_about); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Friends -------------------------------------------------------------------------------------------

create or replace function public.add_friend(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.assert_signed_in(); v_a uuid := least(v_user, p_user); v_b uuid := greatest(v_user, p_user);
  f public.friendships; v_chat uuid;
begin
  if p_user = v_user then raise exception 'cannot_add_self'; end if;
  if not exists (select 1 from public.profiles where id = p_user and deleted_at is null and suspended_at is null) then
    raise exception 'player_unavailable';
  end if;
  if public.is_blocked_either(v_user, p_user) then raise exception 'player_unavailable'; end if;
  perform public.check_rate_limit('add_friend', 100, interval '1 day');

  select * into f from public.friendships where user_a = v_a and user_b = v_b for update;
  if not found then
    v_chat := public.ensure_dm_chat(v_user, p_user);
    -- Two first adds can land at the same instant, one from each player. Only one row may exist; the
    -- add that loses the race carries on below as the add-back it has become.
    insert into public.friendships (user_a, user_b, status, requested_by, dm_chat_id) values (v_a, v_b, 'pending', v_user, v_chat)
    on conflict (user_a, user_b) do nothing;
    if found then
      perform public.system_message(v_chat, public.display_name(v_user) || ' added ' || public.display_name(p_user),
        jsonb_build_object('event', 'friend_added', 'actor', v_user, 'subject', p_user));
      perform public.notify(p_user, 'friend_added', 'Courtly', public.display_name(v_user) || ' added you',
        'courtly://chat/' || v_chat, 'chat-' || v_chat, jsonb_build_object('chat_id', v_chat, 'user_id', v_user));
      return jsonb_build_object('relationship', 'requested', 'dm_chat_id', v_chat);
    end if;
    select * into f from public.friendships where user_a = v_a and user_b = v_b for update;
  end if;

  v_chat := coalesce(f.dm_chat_id, public.ensure_dm_chat(v_user, p_user));
  if f.status = 'pending' and f.requested_by <> v_user then
    update public.friendships set status = 'accepted', accepted_at = now(), dm_chat_id = v_chat where user_a = v_a and user_b = v_b;
    perform public.system_message(v_chat, public.display_name(v_user) || ' added you back. Say hi',
      jsonb_build_object('event', 'friend_accepted', 'actor', v_user, 'subject', p_user));
    perform public.notify(p_user, 'friend_accepted', 'Courtly', public.display_name(v_user) || ' added you back',
      'courtly://chat/' || v_chat, 'chat-' || v_chat, jsonb_build_object('chat_id', v_chat, 'user_id', v_user));
  end if;
  return jsonb_build_object('relationship', public.relationship_to(v_user, p_user), 'dm_chat_id', v_chat);
end $$;

-- Moderation and deletion ------------------------------------------------------------------------------

create or replace function private.suspend_user(p_user uuid, p_suspend boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  update public.profiles set suspended_at = case when p_suspend then now() else null end where id = p_user;
  -- The sign-in stops refreshing as well, so the app returns to Welcome within the hour instead of
  -- carrying on with the token it holds.
  update auth.users set banned_until = case when p_suspend then now() + interval '100 years' else null end where id = p_user;
  if p_suspend then
    for r in select id from public.hits where host_id = p_user and status in ('open', 'confirmed') and starts_at > now() loop
      perform public.close_hit(r.id);
    end loop;
    -- Nothing of theirs stays in front of a host.
    update public.join_requests set status = 'cancelled', responded_at = now() where user_id = p_user and status = 'pending';
    update public.hit_invites set status = 'cancelled' where target_user_id = p_user and status = 'open';
    delete from public.device_tokens where user_id = p_user;
  end if;
end $$;

create or replace function public.internal_delete_account(p_user uuid, p_mode text default 'full') returns jsonb
language plpgsql security definer set search_path = public as $$
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
    delete from public.reports where p_user in (reporter_id, reported_id);
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
end $$;
