-- Two lookups that would otherwise scan a whole table as it grows: a report's notices are found by their
-- collapse id when the report goes, and a deleted player's messages by sender when the account is removed.
create index if not exists notifications_collapse_idx on public.notifications (collapse_id) where collapse_id is not null;
create index if not exists messages_sender_idx on public.messages (sender_id) where sender_id is not null;

-- Notification rows are push bookkeeping (the app's badge and lists come from requests, invites and
-- messages), and every message to every member adds one. The daily purge drops them after 30 days.
create or replace function public.purge_old_reports() returns void
language sql security definer set search_path = public as $$
  delete from public.reports where created_at < now() - interval '90 days';
  delete from public.rate_limits where window_start < now() - interval '2 days';
  delete from public.notifications where created_at < now() - interval '30 days';
$$;
