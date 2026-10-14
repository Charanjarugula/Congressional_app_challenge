-- Scheduled work, the push webhook, moderation, and the service-role functions used by Edge Functions.

-- Every five minutes: expire, close, mark played, remind, day-after. Each step is "due and not yet sent".
create or replace function public.run_hit_scheduler() returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_local_hour integer := extract(hour from now() at time zone 'America/New_York');
begin
  -- Open hits nobody joined, now in the past.
  for r in update public.hits set status = 'expired' where status = 'open' and starts_at < now() returning id loop
    update public.join_requests set status = 'expired', responded_at = now() where hit_id = r.id and status = 'pending';
    update public.hit_invites set status = 'expired' where hit_id = r.id and status = 'open';
  end loop;

  -- Invite cards past their deadline.
  for r in update public.hit_invites set status = 'expired' where status = 'open' and expires_at < now() returning id, chat_id loop
    perform public.system_message(r.chat_id, 'Hit request closed', jsonb_build_object('event', 'invite_expired', 'invite_id', r.id));
  end loop;

  -- Confirmed hits that have finished.
  for r in update public.hits set status = 'played'
           where status = 'confirmed' and starts_at + (duration_min || ' minutes')::interval < now() returning id loop
    update public.join_requests set status = 'expired', responded_at = now() where hit_id = r.id and status = 'pending';
    update public.profiles p set hits_played = hits_played + 1
    from public.hit_players hp where hp.hit_id = r.id and hp.left_at is null and p.id = hp.user_id;
  end loop;

  -- Day-before reminder.
  for r in update public.hits set reminder_day_sent_at = now()
           where status = 'confirmed' and reminder_day_sent_at is null
             and starts_at <= now() + interval '24 hours 5 minutes' and starts_at > now() + interval '1 hour'
             and created_at <= starts_at - interval '24 hours'
           returning id loop
    perform public.notify(hp.user_id, 'reminder_day', 'Hit tomorrow',
      public.hit_push_label(r.id) || ' · ' || coalesce((select string_agg(public.display_name(o.user_id), ', ')
        from public.hit_players o where o.hit_id = r.id and o.left_at is null and o.user_id <> hp.user_id), ''),
      'courtly://hit/' || r.id, 'hit-' || r.id, jsonb_build_object('hit_id', r.id))
    from public.hit_players hp where hp.hit_id = r.id and hp.left_at is null;
  end loop;

  -- One-hour reminder.
  for r in update public.hits set reminder_hour_sent_at = now()
           where status = 'confirmed' and reminder_hour_sent_at is null
             and starts_at <= now() + interval '65 minutes' and starts_at > now()
           returning id loop
    perform public.notify(hp.user_id, 'reminder_hour', 'Hit in 1 hour', public.hit_push_label(r.id),
      'courtly://hit/' || r.id, 'hit-' || r.id, jsonb_build_object('hit_id', r.id))
    from public.hit_players hp where hp.hit_id = r.id and hp.left_at is null;
  end loop;

  -- Day-after check, from 9 AM local the day after.
  if v_local_hour >= 9 then
    for r in update public.hits set day_after_sent_at = now()
             where status = 'played' and day_after_sent_at is null
               and (starts_at at time zone 'America/New_York')::date < (now() at time zone 'America/New_York')::date
             returning id loop
      perform public.notify(hp.user_id, 'day_after_check', 'Courtly',
        'Did ' || public.display_name(o.user_id) || ' show up?',
        'courtly://check/' || r.id || '/' || o.user_id, 'check-' || r.id,
        jsonb_build_object('hit_id', r.id, 'about_user_id', o.user_id))
      from public.hit_players hp
      join public.hit_players o on o.hit_id = hp.hit_id and o.user_id <> hp.user_id and o.left_at is null
      where hp.hit_id = r.id and hp.left_at is null;
    end loop;
  end if;
end $$;

-- Push outbox: a database webhook per notification, plus a sweep for anything the function missed.
create or replace function public.post_push(p_notification uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_url text := private.setting('functions_url'); v_secret text := private.setting('webhook_secret');
begin
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(
    url := v_url || '/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    body := jsonb_build_object('notification_id', p_notification),
    timeout_milliseconds := 8000
  );
end $$;

create or replace function public.notifications_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('friend_added', 'friend_accepted') then
    update public.notifications set pushed_at = now(), push_status = 'in_app_only' where id = new.id;
    return new;
  end if;
  perform public.post_push(new.id);
  return new;
end $$;

create trigger notifications_push after insert on public.notifications
  for each row execute function public.notifications_after_insert();

create or replace function public.resend_unpushed() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from public.notifications
           where pushed_at is null and push_attempts < 3 and created_at < now() - interval '2 minutes'
             and created_at > now() - interval '1 day' loop
    perform public.post_push(r.id);
  end loop;
end $$;

-- Reports older than 90 days about players are purged; everything else is kept.
create or replace function public.purge_old_reports() returns void
language sql security definer set search_path = public as $$
  delete from public.reports where created_at < now() - interval '90 days';
  delete from public.rate_limits where window_start < now() - interval '2 days';
$$;

select cron.schedule('courtly-hit-scheduler', '*/5 * * * *', $$select public.run_hit_scheduler()$$);
select cron.schedule('courtly-push-resend', '*/10 * * * *', $$select public.resend_unpushed()$$);
select cron.schedule('courtly-purge-reports', '0 4 * * *', $$select public.purge_old_reports()$$);

-- Moderation -------------------------------------------------------------------------

create or replace view private.moderation_queue as
  select r.id, r.created_at, r.status, r.reason, r.auto, r.details,
         public.display_name(r.reporter_id) as reporter, r.reporter_id,
         public.display_name(r.reported_id) as reported, r.reported_id,
         (select count(*) from public.reports x where x.reported_id = r.reported_id) as reports_about_reported,
         (select no_shows from public.profiles p where p.id = r.reported_id) as no_shows
  from public.reports r
  order by r.created_at desc;

-- Admins run this from the SQL editor. Cancels the player's future hits and signs them out of the app's data.
create or replace function private.suspend_user(p_user uuid, p_suspend boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  update public.profiles set suspended_at = case when p_suspend then now() else null end where id = p_user;
  if p_suspend then
    for r in select id from public.hits where host_id = p_user and status in ('open', 'confirmed') and starts_at > now() loop
      perform public.close_hit(r.id);
    end loop;
    delete from public.device_tokens where user_id = p_user;
  end if;
end $$;

-- Service-role functions for Edge Functions ----------------------------------------------
-- Callable only with the service role key; the functions verify the user's JWT first.

create or replace function public.internal_store_apple_token(p_user uuid, p_refresh_token text) returns void
language plpgsql security definer set search_path = public as $$
declare v_secret uuid;
begin
  -- Vault names are unique: a second sign-in updates the stored secret instead of creating another.
  select vault_secret_id into v_secret from public.apple_tokens where user_id = p_user;
  if v_secret is null then
    select id into v_secret from vault.secrets where name = 'apple-refresh-' || p_user::text;
  end if;
  if v_secret is not null then
    perform vault.update_secret(v_secret, p_refresh_token);
  else
    select vault.create_secret(p_refresh_token, 'apple-refresh-' || p_user::text) into v_secret;
  end if;
  insert into public.apple_tokens (user_id, vault_secret_id) values (p_user, v_secret)
  on conflict (user_id) do update set vault_secret_id = excluded.vault_secret_id, created_at = now();
end $$;

create or replace function public.internal_apple_refresh_token(p_user uuid) returns text
language sql security definer set search_path = public as $$
  select s.decrypted_secret from public.apple_tokens t join vault.decrypted_secrets s on s.id = t.vault_secret_id
  where t.user_id = p_user;
$$;

-- Everything account deletion does inside the database. Apple revocation, storage and the auth
-- user are handled by the delete-account function around this call.
create or replace function public.internal_delete_account(p_user uuid, p_mode text default 'full') returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; v_vault uuid;
begin
  select vault_secret_id into v_vault from public.apple_tokens where user_id = p_user;

  if p_mode = 'underage' then
    -- Someone under 13 never finished onboarding; nothing of theirs stays, not even an anonymized row.
    -- They may already have sent friend requests (which open DMs), blocked or reported someone.
    delete from public.device_tokens where user_id = p_user;
    delete from public.notifications where user_id = p_user;
    delete from public.join_requests where user_id = p_user;
    delete from public.hit_invites where created_by = p_user or target_user_id = p_user;
    delete from public.friendships where p_user in (user_a, user_b);
    delete from public.blocks where p_user in (blocker_id, blocked_id);
    delete from public.reports where p_user in (reporter_id, reported_id);
    delete from public.attendance_checks where p_user in (user_id, about_user_id);
    delete from public.rate_limits where user_id = p_user;
    delete from public.apple_tokens where user_id = p_user;
    delete from public.admin_users where user_id = p_user;
    if v_vault is not null then delete from vault.secrets where id = v_vault; end if;
    for r in select c.id from public.chats c join public.chat_members m on m.chat_id = c.id where c.type = 'dm' and m.user_id = p_user loop
      update public.chats set last_message_id = null where id = r.id;
      delete from public.messages where chat_id = r.id;
      delete from public.chat_members where chat_id = r.id;
      delete from public.chats where id = r.id;
    end loop;
    delete from public.messages where sender_id = p_user;
    delete from public.chat_members where user_id = p_user;
    delete from public.hit_players where user_id = p_user;
    delete from public.hits where host_id = p_user;
    delete from public.profiles where id = p_user;
    return jsonb_build_object('deleted', true);
  end if;

  -- Future hits I host are cancelled; future hits I joined are left.
  for r in select id from public.hits where host_id = p_user and status in ('open', 'confirmed') and starts_at > now() loop
    perform public.close_hit(r.id, 'The host left Courtly.');
  end loop;
  for r in select h.id, h.host_id, h.chat_id from public.hits h join public.hit_players hp on hp.hit_id = h.id
           where hp.user_id = p_user and hp.role = 'player' and hp.left_at is null and h.status in ('open', 'confirmed') and h.starts_at > now() loop
    update public.hit_players set left_at = now() where hit_id = r.id and user_id = p_user;
    update public.hits set spots_open = spots_open + 1,
      status = case when exists (select 1 from public.hit_players x where x.hit_id = r.id and x.role = 'player' and x.left_at is null)
                    then status else 'open' end
    where id = r.id;
    perform public.notify(r.host_id, 'player_left', 'Courtly', 'A player left ' || public.hit_push_label(r.id) || '. The spot is open again.',
      'courtly://hit/' || r.id, 'hit-' || r.id, jsonb_build_object('hit_id', r.id));
  end loop;

  delete from public.device_tokens where user_id = p_user;
  delete from public.notifications where user_id = p_user;
  delete from public.join_requests where user_id = p_user;
  delete from public.hit_invites where created_by = p_user or target_user_id = p_user;
  delete from public.friendships where p_user in (user_a, user_b);
  delete from public.blocks where p_user in (blocker_id, blocked_id);
  delete from public.attendance_checks where user_id = p_user;
  delete from public.rate_limits where user_id = p_user;
  delete from public.apple_tokens where user_id = p_user;
  delete from public.admin_users where user_id = p_user;
  if v_vault is not null then delete from vault.secrets where id = v_vault; end if;

  -- Direct messages go; group and hit chats keep the thread with my messages anonymized.
  for r in select c.id from public.chats c join public.chat_members m on m.chat_id = c.id where c.type = 'dm' and m.user_id = p_user loop
    update public.chats set last_message_id = null where id = r.id;
    delete from public.messages where chat_id = r.id;
    delete from public.chat_members where chat_id = r.id;
    delete from public.chats where id = r.id;
  end loop;
  update public.messages set sender_id = null where sender_id = p_user;
  for r in select chat_id from public.chat_members where user_id = p_user and left_at is null loop
    update public.chat_members set left_at = now() where chat_id = r.chat_id and user_id = p_user;
    perform public.system_message(r.chat_id, 'A player left Courtly', jsonb_build_object('event', 'member_left'));
  end loop;

  update public.profiles set
    first_name = 'Deleted', last_name = '', photo_path = null, birthday = null, gender = null,
    phone_e164 = null, phone_hash = null, email_hash = null, home_point = null, zip = null, area_label = null,
    availability_mask = 0, busy_mask_week = null, deleted_at = now()
  where id = p_user;
  return jsonb_build_object('deleted', true);
end $$;

-- Moderators (public.admin_users) are told about every report the moment it lands.
create or replace function public.reports_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify(a.user_id, 'report', 'Courtly',
    'New report: ' || replace(new.reason::text, '_', ' ') || case when new.auto then ' (automatic)' else '' end,
    'courtly://play', 'report-' || new.id::text, jsonb_build_object('report_id', new.id, 'reported_id', new.reported_id))
  from public.admin_users a where a.user_id not in (new.reporter_id, new.reported_id);
  return new;
end $$;

create trigger reports_notify after insert on public.reports for each row execute function public.reports_after_insert();

-- A report that is withdrawn (a "No" taken back) or purged takes its notice with it.
create or replace function public.reports_after_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.notifications where collapse_id = 'report-' || old.id::text;
  return old;
end $$;

create trigger reports_forget after delete on public.reports for each row execute function public.reports_after_delete();

grant execute on all functions in schema public to authenticated, service_role;
revoke execute on function public.internal_store_apple_token(uuid, text) from public, anon, authenticated;
revoke execute on function public.internal_apple_refresh_token(uuid) from public, anon, authenticated;
revoke execute on function public.internal_delete_account(uuid, text) from public, anon, authenticated;
revoke execute on function public.run_hit_scheduler() from public, anon, authenticated;
revoke execute on function public.resend_unpushed() from public, anon, authenticated;
revoke execute on function public.purge_old_reports() from public, anon, authenticated;
revoke execute on function public.post_push(uuid) from public, anon, authenticated;
revoke execute on function public.notify(uuid, public.notification_kind, text, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.add_player(uuid, uuid, public.player_source) from public, anon, authenticated;
revoke execute on function public.post_message(uuid, uuid, public.message_type, text, jsonb, uuid) from public, anon, authenticated;
revoke execute on function public.system_message(uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.ensure_hit_chat(uuid) from public, anon, authenticated;
revoke execute on function public.ensure_dm_chat(uuid, uuid) from public, anon, authenticated;
revoke execute on all functions in schema public from anon;
