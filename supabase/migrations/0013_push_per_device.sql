-- Push delivery is tracked per device. A player with two phones used to count as delivered once either
-- phone took the push; the sweep then never came back for the other. Each successful device token is
-- recorded here, the notification is finished only when every current device has it, and a retry sends
-- only to the phones still missing it.
alter table public.notifications add column if not exists push_delivered text[] not null default '{}';
