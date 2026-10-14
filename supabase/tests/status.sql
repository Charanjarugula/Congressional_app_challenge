-- One row per fact about the deployed project, for the deploy's status step. Reads only.
select 'migrations' as k, count(*)::text || ' recorded (' || count(sha256)::text || ' with hash), last ' || max(name) as v from private.app_migrations
union all select 'cron_jobs', string_agg(jobname || ' (' || schedule || ')', ', ' order by jobname) from cron.job
union all select 'cron_failed_24h', count(*)::text from cron.job_run_details where status <> 'succeeded' and start_time > now() - interval '24 hours'
union all select 'cron_last_run', coalesce(to_char(max(start_time) at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC', 'never') from cron.job_run_details
union all select 'settings', string_agg(key, ', ' order by key) from private.settings
union all select 'auth_triggers', string_agg(tgname, ', ' order by tgname) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal
union all select 'realtime_tables', string_agg(tablename, ', ' order by tablename) from pg_publication_tables where pubname = 'supabase_realtime'
union all select 'avatars_bucket', case when exists (select 1 from storage.buckets where id = 'avatars') then 'present' else 'MISSING' end
union all select 'storage_policies', count(*)::text from pg_policies where schemaname = 'storage'
union all select 'api_functions', count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))::text || ' callable by the app of ' || count(*)::text || ' public'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
union all select 'chats_readable_by_app', has_table_privilege('authenticated', 'public.chats', 'select')::text
union all select 'moderators', coalesce(string_agg(p.first_name || ' ' || p.last_name, ', '), 'none yet') from public.admin_users a join public.profiles p on p.id = a.user_id
union all select 'profiles', count(*)::text || ' (' || count(*) filter (where onboarding_completed_at is not null)::text || ' onboarded, '
  || count(*) filter (where suspended_at is not null)::text || ' suspended, ' || count(*) filter (where deleted_at is not null)::text || ' deleted)' from public.profiles
union all select 'courts', count(*)::text || ' (' || count(*) filter (where source <> 'seed')::text || ' added by players)' from public.courts
union all select 'hits', coalesce(string_agg(status || ' ' || c, ', ' order by status), 'none') from (select status::text, count(*) c from public.hits group by 1) s
union all select 'chats', coalesce(string_agg(type || ' ' || c, ', ' order by type), 'none') from (select type::text, count(*) c from public.chats group by 1) s
union all select 'push', coalesce(string_agg(push_status || ' ' || c, ', ' order by push_status), 'none') from (select push_status::text, count(*) c from public.notifications group by 1) s
union all select 'reports_open', count(*)::text from public.reports
union all select 'review_account', case when exists (select 1 from auth.users where email = 'reviewer@courtly.app') then 'present' else 'absent' end
union all select 'demo_players', count(*)::text from auth.users where email like 'demo.%@courtly.app';
