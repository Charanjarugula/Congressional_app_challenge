-- Chats: groups, sending, reading, the inbox and thread pages.

create or replace function public.filter_text(p_text text) returns void
language plpgsql stable security definer set search_path = public as $$
declare v_words text[];
begin
  v_words := regexp_split_to_array(lower(regexp_replace(coalesce(p_text, ''), '[^[:alnum:][:space:]]', ' ', 'g')), '\s+');
  if exists (select 1 from public.blocked_terms t where t.term = any(v_words)) then raise exception 'filtered'; end if;
end $$;

-- System lines about friends read differently to each side: "You added Ana R. back" vs "Luis M. added you back".
create or replace function public.message_text(p_message uuid, p_viewer uuid default auth.uid()) returns text
language sql stable security definer set search_path = public as $$
  select case
    when m.type <> 'system' then m.body
    when m.payload->>'event' = 'friend_added' and (m.payload->>'actor')::uuid = p_viewer
      then 'You added ' || public.display_name((m.payload->>'subject')::uuid)
    when m.payload->>'event' = 'friend_added' and (m.payload->>'subject')::uuid = p_viewer
      then public.display_name((m.payload->>'actor')::uuid) || ' added you'
    when m.payload->>'event' = 'friend_accepted' and (m.payload->>'actor')::uuid = p_viewer
      then 'You added ' || public.display_name((m.payload->>'subject')::uuid) || ' back. Say hi'
    when m.payload->>'event' = 'friend_accepted' and (m.payload->>'subject')::uuid = p_viewer
      then public.display_name((m.payload->>'actor')::uuid) || ' added you back. Say hi'
    else m.body end
  from public.messages m where m.id = p_message;
$$;

create or replace function public.message_json(p_message uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', m.id, 'chat_id', m.chat_id, 'sender', case when m.sender_id is null then null else public.player_card(m.sender_id) end,
    'type', m.type, 'body', public.message_text(m.id, auth.uid()), 'payload', m.payload, 'client_id', m.client_id, 'created_at', m.created_at,
    'invite', case when m.type = 'hit_invite' then public.invite_json((m.payload->>'invite_id')::uuid) else null end
  )
  from public.messages m where m.id = p_message;
$$;

create or replace function public.chat_display_name(p_chat uuid, p_viewer uuid) returns text
language sql stable security definer set search_path = public as $$
  select case c.type
    when 'group' then c.name
    when 'dm' then (select public.display_name(m.user_id) from public.chat_members m where m.chat_id = c.id and m.user_id <> p_viewer limit 1)
    when 'hit' then coalesce(
      (select string_agg(public.display_name(m.user_id), ', ') from public.chat_members m
       where m.chat_id = c.id and m.user_id <> p_viewer and m.left_at is null),
      'Hit chat')
    end
  from public.chats c where c.id = p_chat;
$$;

create or replace function public.chat_json(p_chat uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'type', c.type, 'name', public.chat_display_name(c.id, p_viewer), 'hit_id', c.hit_id,
    'members', (select jsonb_agg(public.player_card(m.user_id) order by m.joined_at)
                from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'member_count', (select count(*) from public.chat_members m where m.chat_id = c.id and m.left_at is null),
    'last_message_at', c.last_message_at,
    'last_message_type', lm.type,
    'preview', case
      when lm.id is not null and lm.type = 'system' then left(public.message_text(lm.id, p_viewer), 120)
      when lm.sender_id is not null and public.is_blocked_either(p_viewer, lm.sender_id) then (
        select case when m.type = 'text' then public.display_name(m.sender_id) || ': ' || left(m.body, 120)
                    when m.type = 'system' then left(public.message_text(m.id, p_viewer), 120)
                    else left(m.body, 120) end
        from public.messages m where m.chat_id = c.id and (m.sender_id is null or not public.is_blocked_either(p_viewer, m.sender_id))
        order by m.created_at desc limit 1)
      else c.last_message_preview end,
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
  left join public.messages lm on lm.id = c.last_message_id
  where c.id = p_chat;
$$;

-- One chat for the header and the group screen; members only.
create or replace function public.get_chat(p_chat uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  return public.chat_json(p_chat, v_user);
end $$;

create or replace function public.create_group_chat(p_name text, p_members uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); v_chat uuid; v_name text := left(btrim(coalesce(p_name, '')), 60); m uuid;
begin
  if v_name = '' then raise exception 'missing_name'; end if;
  perform public.filter_text(v_name);
  if cardinality(p_members) = 0 then raise exception 'missing_members'; end if;
  foreach m in array p_members loop
    if not public.is_friend(v_user, m) then raise exception 'not_friends'; end if;
  end loop;
  insert into public.chats (type, name, created_by) values ('group', v_name, v_user) returning id into v_chat;
  insert into public.chat_members (chat_id, user_id) select v_chat, u from unnest(array_append(p_members, v_user)) as u
  on conflict do nothing;
  perform public.system_message(v_chat, public.display_name(v_user) || ' created ' || v_name,
    jsonb_build_object('event', 'group_created', 'actor', v_user));
  return public.chat_json(v_chat, v_user);
end $$;

create or replace function public.add_chat_members(p_chat uuid, p_members uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); m uuid;
begin
  if not exists (select 1 from public.chats where id = p_chat and type = 'group') then raise exception 'not_a_group'; end if;
  if not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  foreach m in array p_members loop
    if not public.is_friend(v_user, m) then raise exception 'not_friends'; end if;
    insert into public.chat_members (chat_id, user_id) values (p_chat, m)
    on conflict (chat_id, user_id) do update set left_at = null;
    perform public.system_message(p_chat, public.display_name(v_user) || ' added ' || public.display_name(m),
      jsonb_build_object('event', 'member_added', 'actor', v_user, 'subject', m));
  end loop;
  return public.chat_json(p_chat, v_user);
end $$;

create or replace function public.leave_chat(p_chat uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded();
begin
  if not exists (select 1 from public.chats where id = p_chat and type = 'group') then raise exception 'not_a_group'; end if;
  update public.chat_members set left_at = now() where chat_id = p_chat and user_id = v_user and left_at is null;
  if not found then raise exception 'not_a_member'; end if;
  perform public.system_message(p_chat, public.display_name(v_user) || ' left',
    jsonb_build_object('event', 'member_left', 'actor', v_user));
end $$;

-- Idempotent on (chat, client_id): a retried send returns the message that already exists.
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

  v_id := public.post_message(p_chat, v_user, 'text', v_body, '{}'::jsonb, p_client_id);
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

create or replace function public.mark_chat_read(p_chat uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.chat_members set last_read_at = now() where chat_id = p_chat and user_id = auth.uid();
end $$;

create or replace function public.set_chat_muted(p_chat uuid, p_muted boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.chat_members set muted = p_muted where chat_id = p_chat and user_id = auth.uid();
end $$;

-- The People tab, newest activity first. Blocked DMs are left out.
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
      order by coalesce(c.last_message_at, c.created_at) desc limit 100
    ) c
  ), '[]'::jsonb);
end $$;

-- One page of a thread, oldest first within the page, before the cursor.
create or replace function public.get_chat_page(
  p_chat uuid, p_before_created_at timestamptz default null, p_before_id uuid default null, p_limit integer default 50
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if not public.is_chat_member(p_chat, v_user) then raise exception 'not_a_member'; end if;
  return jsonb_build_object(
    'chat', public.chat_json(p_chat, v_user),
    'messages', coalesce((
      select jsonb_agg(public.message_json(m.id) order by m.created_at, m.id)
      from (
        select m.id, m.created_at from public.messages m
        where m.chat_id = p_chat
          and (m.sender_id is null or not public.is_blocked_either(v_user, m.sender_id))
          and (p_before_created_at is null or (m.created_at, m.id) < (p_before_created_at, p_before_id))
        order by m.created_at desc, m.id desc limit least(p_limit, 100)
      ) m
    ), '[]'::jsonb)
  );
end $$;
