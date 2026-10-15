-- A host who leaves a hit with other players in it hands it to whoever joined first. The hit goes
-- on; the chat says who is hosting now. A host alone in a hit still cancels it.

create or replace function public.leave_hit(p_hit uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_remaining integer; v_next uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found then raise exception 'hit_not_found'; end if;
  if h.status not in ('open', 'confirmed') then raise exception 'hit_closed'; end if;
  if h.starts_at <= now() then raise exception 'hit_started'; end if;

  if h.host_id = v_user then
    select user_id into v_next from public.hit_players
    where hit_id = p_hit and role = 'player' and left_at is null order by joined_at limit 1;
    if v_next is null then raise exception 'host_cannot_leave'; end if;
    update public.hit_players set left_at = now() where hit_id = p_hit and user_id = v_user and left_at is null;
    update public.hit_players set role = 'host' where hit_id = p_hit and user_id = v_next;
    update public.hits set host_id = v_next where id = p_hit;
    perform public.system_message(h.chat_id,
      public.display_name(v_user) || ' left the hit · ' || public.display_name(v_next) || ' is hosting now',
      jsonb_build_object('event', 'host_changed', 'actor', v_user, 'subject', v_next));
    perform public.notify(v_next, 'player_left', 'Courtly',
      public.display_name(v_user) || ' left ' || public.hit_push_label(p_hit) || '. You’re hosting now.',
      'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  else
    update public.hit_players set left_at = now() where hit_id = p_hit and user_id = v_user and left_at is null;
    if not found then raise exception 'not_a_player'; end if;
    perform public.system_message(h.chat_id, public.display_name(v_user) || ' left the hit',
      jsonb_build_object('event', 'player_left', 'actor', v_user));
    perform public.notify(h.host_id, 'player_left', 'Courtly',
      public.display_name(v_user) || ' can’t make ' || public.hit_push_label(p_hit) || '. The spot is open again.',
      'courtly://hit/' || p_hit, 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
  end if;

  -- Either way a joiner's spot is free again: the leaver's, or the one the new host moved out of.
  select count(*) into v_remaining from public.hit_players where hit_id = p_hit and role = 'player' and left_at is null;
  update public.hits set spots_open = spots_open + 1, status = case when v_remaining = 0 then 'open' else status end
  where id = p_hit;
  update public.chat_members cm set left_at = now() from public.chats c
  where c.id = cm.chat_id and cm.chat_id = h.chat_id and cm.user_id = v_user and c.type = 'hit';
  return public.hit_json(p_hit, v_user);
end $$;

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
    when m.payload->>'event' in ('player_left', 'member_left', 'hit_cancelled', 'host_changed') and (m.payload->>'actor')::uuid = p_viewer
      then 'You ' || substring(m.body from length(public.display_name((m.payload->>'actor')::uuid)) + 2)
    else m.body end
  from public.messages m where m.id = p_message;
$$;
