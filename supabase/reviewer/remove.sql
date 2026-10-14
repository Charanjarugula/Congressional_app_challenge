-- Deletes the App Review account outright. It is marked as never onboarded first, so the deletion
-- keeps nothing of it, not even the anonymized row a real player's deletion leaves behind.
do $$
declare v_id uuid;
begin
  select id into v_id from auth.users where email = 'reviewer@courtly.app';
  if v_id is null then return; end if;
  update public.profiles set onboarding_completed_at = null where id = v_id;
  perform public.internal_delete_account(v_id, 'underage');
  delete from auth.users where id = v_id;
end $$;
