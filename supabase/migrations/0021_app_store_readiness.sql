-- What App Review asks of an app where people meet and talk: adults only, a way to report a single
-- message, and reports that reach a person. Courtly is 18+ from here on.

-- 18 and older.
create or replace function public.complete_onboarding() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); p public.profiles;
begin
  select * into p from public.profiles where id = v_user;
  if btrim(p.first_name) = '' then raise exception 'missing_name'; end if;
  if p.birthday is null then raise exception 'missing_birthday'; end if;
  if p.birthday > (current_date - interval '18 years') then raise exception 'underage'; end if;
  if p.level is null then raise exception 'missing_level'; end if;
  if cardinality(p.formats) = 0 then raise exception 'missing_formats'; end if;
  if p.home_point is null then raise exception 'missing_location'; end if;

  update public.profiles set onboarding_completed_at = coalesce(onboarding_completed_at, now()) where id = v_user;
  return public.profile_json(v_user);
end $$;

-- A report can point at one message; its text is kept with the report in case the message goes.
alter table public.reports add column if not exists message_id uuid references public.messages (id) on delete set null;
alter table public.reports add column if not exists message_body text;

drop function if exists public.report_user(uuid, public.report_reason, text, boolean, uuid);
create or replace function public.report_user(
  p_user uuid, p_reason public.report_reason, p_details text default null, p_also_block boolean default false,
  p_hit uuid default null, p_message uuid default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); m public.messages;
begin
  if p_user = v_user then raise exception 'cannot_report_self'; end if;
  if p_message is not null then
    select * into m from public.messages where id = p_message;
    -- Only a message the reporter could read, written by the player reported.
    if not found or m.sender_id is distinct from p_user or not public.was_chat_member(m.chat_id, v_user) then
      raise exception 'not_a_member';
    end if;
  end if;
  perform public.check_rate_limit('report_user', 20, interval '1 day');
  insert into public.reports (reporter_id, reported_id, hit_id, reason, details, also_blocked, message_id, message_body)
  values (v_user, p_user, p_hit, p_reason, left(p_details, 1000), p_also_block, p_message, m.body);
  if p_also_block then perform public.block_user(p_user); end if;
end $$;
grant execute on function public.report_user(uuid, public.report_reason, text, boolean, uuid, uuid) to authenticated;

-- Every report is emailed to the support inbox, besides the in-app notice to moderators.
create or replace function public.post_report_email(p_report uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_url text := private.setting('functions_url'); v_secret text := private.setting('webhook_secret');
begin
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(
    url := v_url || '/report-email',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    body := jsonb_build_object('report_id', p_report),
    timeout_milliseconds := 8000
  );
end $$;

create or replace function public.reports_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify(a.user_id, 'report', 'Courtly',
    'New report: ' || replace(new.reason::text, '_', ' ') || case when new.auto then ' (automatic)' else '' end,
    'courtly://play', 'report-' || new.id::text, jsonb_build_object('report_id', new.id, 'reported_id', new.reported_id))
  from public.admin_users a where a.user_id not in (new.reporter_id, new.reported_id);
  perform public.post_report_email(new.id);
  return new;
end $$;

revoke execute on function public.post_report_email(uuid) from public, anon, authenticated;
