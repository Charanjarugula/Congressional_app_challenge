-- Friend requests, the way people expect them: an add is a request the other player confirms or
-- deletes. Nothing opens until they confirm; a direct message starts then, with a line saying so.
-- A deleted request is silent: the asker still sees "Requested" and can't ask again, while the player
-- who deleted it sees them as a stranger and can add them later, which makes the two friends at once.
-- An asker can take a request back. Requests count on the People badge. Mutual friends come back as
-- cards wherever a player is shown.

alter table public.friendships add column if not exists declined_at timestamptz;

-- Reads ------------------------------------------------------------------------------------

create or replace function public.relationship_to(p_user uuid, p_other uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.is_blocked_either(p_user, p_other) then 'blocked'
    when f.status = 'accepted' then 'friend'
    when f.status = 'pending' and f.requested_by = p_user then 'requested'
    when f.status = 'pending' and f.declined_at is null then 'requested_me'
    else 'none' end
  from (select 1) x
  left join public.friendships f on f.user_a = least(p_user, p_other) and f.user_b = greatest(p_user, p_other);
$$;

create or replace function public.mutual_friend_cards(p_user uuid, p_other uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.player_card(p.id) order by p.first_name, p.last_name), '[]'::jsonb)
  from public.profiles p
  where p.id <> p_user and p.id <> p_other and public.is_active_user(p.id)
    and public.is_friend(p_user, p.id) and public.is_friend(p_other, p.id);
$$;

create or replace function public.friend_request_count(p_user uuid) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from public.friendships f
  where p_user in (f.user_a, f.user_b) and f.status = 'pending' and f.requested_by <> p_user and f.declined_at is null
    and public.is_active_user(f.requested_by) and not public.is_blocked_either(p_user, f.requested_by);
$$;

-- Who is waiting on the caller, newest first, and whom the caller is waiting on.
create or replace function public.get_friend_requests() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
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
end $$;

create or replace function public.badge_count(p_user uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from public.join_requests r join public.hits h on h.id = r.hit_id
     where h.host_id = p_user and r.status = 'pending' and h.status in ('open', 'confirmed') and h.starts_at > now())
    + (select count(*) from public.hit_invites i join public.hits h on h.id = i.hit_id
       where i.target_user_id = p_user and i.status = 'open' and i.expires_at > now() and h.status in ('open', 'confirmed') and h.starts_at > now())
    + (select count(*) from public.chat_members cm
       where cm.user_id = p_user and cm.left_at is null and exists (
         select 1 from public.messages m where m.chat_id = cm.chat_id and m.sender_id is distinct from p_user
           and m.created_at > coalesce(cm.last_read_at, '-infinity'::timestamptz)
           and (m.sender_id is null or not public.is_blocked_either(p_user, m.sender_id))))
    + public.friend_request_count(p_user)
  )::integer;
$$;

-- Player profile screen: card, mutual friends (names and cards), relationship, their open hits I can see.
create or replace function public.get_player(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_signed_in(); f public.friendships;
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
    else m.body end
  from public.messages m where m.id = p_message;
$$;

-- Writes -----------------------------------------------------------------------------------

-- The two become friends: the DM opens (or comes back), with a line in it, and the asker is told.
create or replace function public.accept_friendship(p_user uuid, p_other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_chat uuid := public.ensure_dm_chat(p_user, p_other);
begin
  update public.friendships set status = 'accepted', accepted_at = now(), declined_at = null, dm_chat_id = v_chat
  where user_a = least(p_user, p_other) and user_b = greatest(p_user, p_other);
  perform public.system_message(v_chat, public.display_name(p_user) || ' accepted ' || public.display_name(p_other) || '’s request',
    jsonb_build_object('event', 'friend_accepted', 'actor', p_user, 'subject', p_other));
  perform public.notify(p_other, 'friend_accepted', 'Courtly', public.display_name(p_user) || ' accepted your friend request',
    'courtly://chat/' || v_chat, 'chat-' || v_chat, jsonb_build_object('chat_id', v_chat, 'user_id', p_user));
  return v_chat;
end $$;

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
end $$;

-- Confirm or delete a request someone sent. Deleting is silent on their side.
create or replace function public.respond_friend_request(p_user uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); f public.friendships; v_chat uuid;
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
end $$;

-- Take back a request that hasn't been answered (or was quietly deleted).
create or replace function public.cancel_friend_request(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  delete from public.friendships
  where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user) and status = 'pending' and requested_by = v_user;
  if not found then raise exception 'request_not_found'; end if;
  delete from public.notifications where user_id = p_user and kind = 'friend_added' and collapse_id = 'friend-' || v_user::text;
  return jsonb_build_object('relationship', 'none', 'dm_chat_id', null);
end $$;

-- Suggestions carry the mutual friends too, so the row can say so.
create or replace function public.get_friend_suggestions(p_known_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  return coalesce((
    with mine as (
      select case when f.user_a = v_user then f.user_b else f.user_a end as id
      from public.friendships f where v_user in (f.user_a, f.user_b) and f.status = 'accepted'
    ),
    candidates as (
      select fof.other, 'mutual' as source, count(*)::int as weight,
             'Friends with ' || array_to_string((array_agg(p.first_name order by p.first_name))[1:2], ' and ') as reason
      from mine
      join public.friendships f on mine.id in (f.user_a, f.user_b) and f.status = 'accepted'
      cross join lateral (select case when f.user_a = mine.id then f.user_b else f.user_a end as other) fof
      join public.profiles p on p.id = mine.id
      where fof.other <> v_user and fof.other not in (select id from mine)
      group by fof.other
      union all
      select m2.user_id, 'group', 2, 'In ' || c.name || ' with you'
      from public.chat_members m1
      join public.chats c on c.id = m1.chat_id and c.type = 'group'
      join public.chat_members m2 on m2.chat_id = c.id and m2.user_id <> v_user and m2.left_at is null
      where m1.user_id = v_user and m1.left_at is null
      union all
      select b.user_id, 'played', 3, 'You hit together on ' || to_char(h.starts_at at time zone 'America/New_York', 'Mon FMDD')
      from public.hit_players a
      join public.hit_players b on b.hit_id = a.hit_id and b.user_id <> v_user
      join public.hits h on h.id = a.hit_id and h.status = 'played'
      where a.user_id = v_user
      union all
      select k, 'contacts', 1, 'In your contacts' from unnest(p_known_ids) as k
    ),
    ranked as (
      select distinct on (other) other, source, reason, weight
      from candidates
      where other <> v_user and public.is_active_user(other) and not public.is_blocked_either(v_user, other)
        and public.relationship_to(v_user, other) = 'none'
      order by other, weight desc
    )
    select jsonb_agg(public.player_card(r.other) || jsonb_build_object(
      'reason', r.reason, 'source', r.source,
      'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, r.other))
    ) order by r.weight desc, r.reason)
    from (select * from ranked order by weight desc limit 20) r
  ), '[]'::jsonb);
end $$;

-- A request and an acceptance now reach the phone like any other notice.
create or replace function public.notifications_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.post_push(new.id);
  return new;
end $$;

-- Existing data: a request that was never answered has no chat yet. Its empty DM goes; one that
-- carries messages (the two share a hit) stays as that hit's thread.
do $$
declare r record;
begin
  for r in select f.user_a, f.user_b, f.dm_chat_id from public.friendships f where f.status = 'pending' and f.dm_chat_id is not null loop
    if not exists (select 1 from public.messages m where m.chat_id = r.dm_chat_id and m.type <> 'system')
       and not exists (select 1 from public.hits h where h.chat_id = r.dm_chat_id) then
      update public.chats set last_message_id = null where id = r.dm_chat_id;
      delete from public.hit_invites where chat_id = r.dm_chat_id;
      delete from public.messages where chat_id = r.dm_chat_id;
      delete from public.chat_members where chat_id = r.dm_chat_id;
      delete from public.chats where id = r.dm_chat_id;
    end if;
    update public.friendships set dm_chat_id = null where user_a = r.user_a and user_b = r.user_b;
  end loop;
end $$;

grant execute on function
  public.respond_friend_request(uuid, boolean),
  public.cancel_friend_request(uuid),
  public.get_friend_requests()
to authenticated;
revoke execute on function public.accept_friendship(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.mutual_friend_cards(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.friend_request_count(uuid) from public, anon, authenticated;
