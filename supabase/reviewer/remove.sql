-- Deletes the App Review account outright. The ordinary deletion runs first: it locks each hit the
-- reviewer joined and gives the seat back, cancels the hits it hosts and leaves its chats. Then, marked
-- as never onboarded, the hard path removes every row that is left, so nothing of the account stays,
-- not even the anonymized profile a real player's deletion leaves behind.
do $$
declare v_id uuid;
begin
  select id into v_id from auth.users where email = 'reviewer@courtly.app';
  if v_id is null then return; end if;
  -- Its messages in groups and other hosts' hit chats go first: the ordinary deletion would only take
  -- the name off them, and the step promises that nothing of the account stays.
  delete from public.messages where sender_id = v_id;
  perform public.internal_delete_account(v_id, 'full');
  -- The hard path drops the hits it hosted; their chats go first, members and messages with them.
  delete from public.chats where type = 'hit' and (created_by = v_id or hit_id in (select id from public.hits where host_id = v_id));
  update public.profiles set onboarding_completed_at = null where id = v_id;
  perform public.internal_delete_account(v_id, 'underage');
  delete from auth.users where id = v_id;
end $$;
