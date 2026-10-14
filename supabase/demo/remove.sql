-- Deletes the demo players' accounts. Runs after reset.sql, which took their world down; the App
-- Review account is the reviewer-remove step's.
do $$
begin
  delete from public.profiles where id in (select id from auth.users where email like 'demo.%@courtly.app');
  delete from auth.users where email like 'demo.%@courtly.app';
end $$;
