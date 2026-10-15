-- A player who leaves a hit chat (or a group) keeps the conversation as it was when they left: the
-- old messages, ending on the line that says they left, and no way to write or see what came after.

create or replace function public.chat_left_at(p_chat uuid, p_user uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select left_at from public.chat_members where chat_id = p_chat and user_id = p_user;
$$;

create or replace function public.was_chat_member(p_chat uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_members where chat_id = p_chat and user_id = p_user);
$$;

create or replace function public.chat_json(p_chat uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'type', c.type, 'name', public.chat_display_name(c.id, p_viewer), 'hit_id', public.chat_pinned_hit(c.id),
    'members', (select jsonb_agg(public.player_card(m.user_id) order by m.joined_at)
                from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'member_count', (select count(*) from public.chat_members m where m.chat_id = c.id and m.left_at is null),
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

create or replace function public.get_chat(p_chat uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if not public.was_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  return public.chat_json(p_chat, v_user);
end $$;

create or replace function public.get_chat_page(
  p_chat uuid, p_before_created_at timestamptz default null, p_before_id uuid default null, p_limit integer default 50
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); v_left timestamptz;
begin
  if not public.was_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  v_left := public.chat_left_at(p_chat, v_user);
  return jsonb_build_object(
    'chat', public.chat_json(p_chat, v_user),
    'messages', coalesce((
      select jsonb_agg(public.message_json(m.id) order by m.created_at, m.id)
      from (
        select m.id, m.created_at from public.messages m
        where m.chat_id = p_chat
          and (v_left is null or m.created_at <= v_left)
          and (m.sender_id is null or not public.is_blocked_either(v_user, m.sender_id))
          and (p_before_created_at is null or (m.created_at, m.id) < (p_before_created_at, p_before_id))
        order by m.created_at desc, m.id desc limit least(p_limit, 100)
      ) m
    ), '[]'::jsonb)
  );
end $$;

-- The inbox keeps chats the player left (hit chats and groups), read-only, under the same retirement rule.
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
            and h.starts_at + make_interval(mins => h.duration_min) < now() - interval '1 day'))
      order by coalesce(c.last_message_at, c.created_at) desc limit 100
    ) c
  ), '[]'::jsonb);
end $$;

-- The line saying they left is the last one the leaver sees, so it goes in before the membership ends.
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

  perform public.system_message(h.chat_id, public.display_name(v_user) || ' left the hit',
    jsonb_build_object('event', 'player_left', 'actor', v_user));
  update public.chat_members cm set left_at = now() from public.chats c
  where c.id = cm.chat_id and cm.chat_id = h.chat_id and cm.user_id = v_user and c.type = 'hit';

  perform public.notify(h.host_id, 'player_left', 'Courtly',
    public.display_name(v_user) || ' can’t make ' || public.hit_push_label(p_hit) || '. The spot is open again.',
    'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  return public.hit_json(p_hit, v_user);
end $$;

create or replace function public.leave_chat(p_chat uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded();
begin
  if not exists (select 1 from public.chats where id = p_chat and type = 'group') then raise exception 'not_a_group'; end if;
  if not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  perform public.system_message(p_chat, public.display_name(v_user) || ' left',
    jsonb_build_object('event', 'member_left', 'actor', v_user));
  update public.chat_members set left_at = now() where chat_id = p_chat and user_id = v_user and left_at is null;
end $$;

revoke execute on function public.chat_left_at(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.was_chat_member(uuid, uuid) from public, anon, authenticated;

-- Lines about the viewer read as "You".
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
    when m.payload->>'event' in ('player_left', 'member_left', 'hit_cancelled') and (m.payload->>'actor')::uuid = p_viewer
      then 'You ' || substring(m.body from length(public.display_name((m.payload->>'actor')::uuid)) + 2)
    else m.body end
  from public.messages m where m.id = p_message;
$$;
