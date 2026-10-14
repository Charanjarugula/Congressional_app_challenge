-- Groups were the one way to write without a daily limit: creating them and adding members now have one,
-- like hits, requests, friends, courts, reports and messages.

create or replace function public.create_group_chat(p_name text, p_members uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); v_chat uuid; v_name text := left(btrim(coalesce(p_name, '')), 60); m uuid;
begin
  if v_name = '' then raise exception 'missing_name'; end if;
  perform public.check_rate_limit('create_group_chat', 20, interval '1 day');
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
  perform public.check_rate_limit('add_chat_members', 100, interval '1 day');
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
