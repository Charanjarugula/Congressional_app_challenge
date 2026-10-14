-- Takes the demo world down: everything the demo players (demo.*@courtly.app) and the App Review
-- account have done between them. The accounts themselves stay, so a phone signed in as one of them
-- stays signed in; remove.sql deletes the players' accounts and the reviewer-remove step the
-- reviewer's. Safe to run when there is nothing to remove.
do $$
declare d uuid[]; r record; v_hit public.hits; v_hits uuid[]; v_chats uuid[];
begin
  select coalesce(array_agg(id), '{}') into d from auth.users where email like 'demo.%@courtly.app' or email = 'reviewer@courtly.app';
  if cardinality(d) = 0 then return; end if;

  -- A seat one of them holds in someone else's hit goes back on offer. The hit is locked and looked at
  -- again first, the way leaving does: a leave or a cancel landing at the same moment must not free the
  -- seat twice or reopen a cancelled hit.
  for r in select hp.hit_id, hp.user_id from public.hit_players hp join public.hits h on h.id = hp.hit_id
           where hp.user_id = any(d) and hp.role = 'player' and hp.left_at is null and not (h.host_id = any(d)) loop
    select * into v_hit from public.hits where id = r.hit_id for update;
    if v_hit.status not in ('open', 'confirmed') or v_hit.starts_at <= now() then continue; end if;
    update public.hit_players set left_at = now() where hit_id = r.hit_id and user_id = r.user_id and left_at is null;
    if not found then continue; end if;
    update public.hits set spots_open = spots_open + 1,
      status = case when exists (select 1 from public.hit_players x where x.hit_id = r.hit_id and x.role = 'player' and x.left_at is null)
                    then status else 'open' end
    where id = r.hit_id;
  end loop;

  -- Their hits with their chats, their direct messages and the groups they started.
  select coalesce(array_agg(id), '{}') into v_hits from public.hits where host_id = any(d);
  select coalesce(array_agg(c.id), '{}') into v_chats from public.chats c
  where c.hit_id = any(v_hits) or c.created_by = any(d)
     or (c.type = 'dm' and exists (select 1 from public.chat_members m where m.chat_id = c.id and m.user_id = any(d)));
  update public.chats set last_message_id = null where id = any(v_chats);
  delete from public.hit_invites where chat_id = any(v_chats) or hit_id = any(v_hits) or created_by = any(d) or target_user_id = any(d);
  delete from public.messages where chat_id = any(v_chats) or sender_id = any(d);
  delete from public.chat_members where chat_id = any(v_chats) or user_id = any(d);
  delete from public.chats where id = any(v_chats);
  delete from public.hits where id = any(v_hits);
  delete from public.hit_players where user_id = any(d);
  delete from public.join_requests where user_id = any(d);
  delete from public.attendance_checks where user_id = any(d) or about_user_id = any(d);
  delete from public.friendships where user_a = any(d) or user_b = any(d);
  delete from public.blocks where blocker_id = any(d) or blocked_id = any(d);
  delete from public.reports where reporter_id = any(d) or reported_id = any(d);
  delete from public.notifications where user_id = any(d);
  delete from public.rate_limits where user_id = any(d);
  update public.profiles set hits_played = 0, no_shows = 0 where id = any(d);
end $$;
