-- Friends, blocks and reports. Add → pending → add back → accepted; the DM is created at the first add.

create or replace function public.find_dm_chat(p_a uuid, p_b uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select c.id from public.chats c
  where c.type = 'dm'
    and exists (select 1 from public.chat_members m where m.chat_id = c.id and m.user_id = p_a)
    and exists (select 1 from public.chat_members m where m.chat_id = c.id and m.user_id = p_b)
  order by c.created_at limit 1;
$$;

create or replace function public.ensure_dm_chat(p_a uuid, p_b uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_chat uuid := public.find_dm_chat(p_a, p_b);
begin
  if v_chat is not null then
    update public.chat_members set left_at = null where chat_id = v_chat and user_id in (p_a, p_b);
    return v_chat;
  end if;
  insert into public.chats (type, created_by) values ('dm', p_a) returning id into v_chat;
  insert into public.chat_members (chat_id, user_id) values (v_chat, p_a), (v_chat, p_b);
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
    v_chat := coalesce(f.dm_chat_id, public.ensure_dm_chat(v_user, p_user));
    if f.status = 'pending' and f.requested_by <> v_user then
      update public.friendships set status = 'accepted', accepted_at = now(), dm_chat_id = v_chat where user_a = v_a and user_b = v_b;
      perform public.system_message(v_chat, public.display_name(v_user) || ' added you back. Say hi',
        jsonb_build_object('event', 'friend_accepted', 'actor', v_user, 'subject', p_user));
      perform public.notify(p_user, 'friend_accepted', 'Courtly', public.display_name(v_user) || ' added you back',
        'courtly://chat/' || v_chat, 'chat-' || v_chat, jsonb_build_object('chat_id', v_chat, 'user_id', v_user));
    end if;
    return jsonb_build_object('relationship', public.relationship_to(v_user, p_user), 'dm_chat_id', v_chat);
  end if;

  v_chat := public.ensure_dm_chat(v_user, p_user);
  insert into public.friendships (user_a, user_b, status, requested_by, dm_chat_id) values (v_a, v_b, 'pending', v_user, v_chat);
  perform public.system_message(v_chat, public.display_name(v_user) || ' added ' || public.display_name(p_user),
    jsonb_build_object('event', 'friend_added', 'actor', v_user, 'subject', p_user));
  perform public.notify(p_user, 'friend_added', 'Courtly', public.display_name(v_user) || ' added you',
    'courtly://chat/' || v_chat, 'chat-' || v_chat, jsonb_build_object('chat_id', v_chat, 'user_id', v_user));
  return jsonb_build_object('relationship', 'requested', 'dm_chat_id', v_chat);
end $$;

create or replace function public.remove_friend(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  delete from public.friendships where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user);
end $$;

-- Hides both players from each other everywhere. Confirmed hits stay; leaving them is explicit.
create or replace function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if p_user = v_user then raise exception 'cannot_block_self'; end if;
  insert into public.blocks (blocker_id, blocked_id) values (v_user, p_user) on conflict do nothing;
  delete from public.friendships where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user);
  update public.join_requests r set status = 'cancelled', responded_at = now()
  from public.hits h where h.id = r.hit_id and r.status = 'pending'
    and ((r.user_id = p_user and h.host_id = v_user) or (r.user_id = v_user and h.host_id = p_user));
  update public.hit_invites set status = 'cancelled'
  where status = 'open' and ((created_by = v_user and target_user_id = p_user) or (created_by = p_user and target_user_id = v_user));
end $$;

create or replace function public.unblock_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_user;
end $$;

create or replace function public.report_user(
  p_user uuid, p_reason public.report_reason, p_details text default null, p_also_block boolean default false, p_hit uuid default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if p_user = v_user then raise exception 'cannot_report_self'; end if;
  perform public.check_rate_limit('report_user', 20, interval '1 day');
  insert into public.reports (reporter_id, reported_id, hit_id, reason, details, also_blocked)
  values (v_user, p_user, p_hit, p_reason, left(p_details, 1000), p_also_block);
  if p_also_block then perform public.block_user(p_user); end if;
end $$;

create or replace function public.get_blocked_players() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.player_card(b.blocked_id) order by b.created_at desc), '[]'::jsonb)
  from public.blocks b where b.blocker_id = public.assert_signed_in();
$$;

-- Accepted friends with their DM, for the People tab and the Invite sheet.
create or replace function public.get_friends() returns jsonb
language sql stable security definer set search_path = public as $$
  with me as (select public.assert_signed_in() as id)
  select coalesce(jsonb_agg(
    public.player_card(other) || jsonb_build_object('dm_chat_id', f.dm_chat_id, 'relationship', 'friend')
    order by (select first_name from public.profiles where id = other)
  ), '[]'::jsonb)
  from me, public.friendships f
  cross join lateral (select case when f.user_a = me.id then f.user_b else f.user_a end as other) o
  where me.id in (f.user_a, f.user_b) and f.status = 'accepted'
    and public.is_active_user(other) and not public.is_blocked_either(me.id, other);
$$;

-- Mutual friends, shared group chats, played together, and contacts the app already matched.
create or replace function public.get_friend_suggestions(p_known_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  return coalesce((
    with candidates as (
      select p.id as other, 'mutual' as source, count(*)::int as weight,
             'Friends with ' || array_to_string((public.mutual_friend_names(v_user, p.id))[1:2], ' and ') as reason
      from public.profiles p
      where exists (select 1 from public.profiles m where public.is_friend(v_user, m.id) and public.is_friend(m.id, p.id))
      group by p.id
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
    select jsonb_agg(public.player_card(r.other) || jsonb_build_object('reason', r.reason, 'source', r.source) order by r.weight desc, r.reason)
    from (select * from ranked order by weight desc limit 20) r
  ), '[]'::jsonb);
end $$;
