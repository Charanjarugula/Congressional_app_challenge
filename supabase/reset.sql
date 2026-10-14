-- Takes the dev project back to before the first migration, so the next `migrate` runs every file
-- again from nothing. Everything the migrations created goes: the scheduled jobs; the policies that
-- guard the avatars bucket; every table, view, function, type and sequence in public, and with them
-- their policies, triggers, indexes and foreign keys, the triggers on auth.users included; the private
-- schema with the migration ledger and the settings; and the accounts, because a sign-in whose profile
-- row is gone could never get one back (the sign-up trigger fires only once). The bucket itself and
-- the files in it stay: Supabase refuses direct deletes from the storage tables so no file is left
-- behind without its row, and the migration reuses the bucket it finds. Nothing is listed by name
-- here: the catalogs say what exists. The deploy's reset step runs this against the dev project only,
-- and the local harness proves the migrations run again after it.
create temp table courtly_reset_log (kind text, name text);

do $$
declare
  r record;
  n bigint;
begin
  for r in select jobid, jobname from cron.job where jobname like 'courtly-%' order by jobname loop
    perform cron.unschedule(r.jobid);
    insert into courtly_reset_log values ('cron job', r.jobname);
  end loop;

  for r in select policyname from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and (coalesce(qual, '') like '%avatars%' or coalesce(with_check, '') like '%avatars%')
           order by policyname loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
    insert into courtly_reset_log values ('storage policy', r.policyname);
  end loop;
  if exists (select 1 from storage.buckets where id = 'avatars') then
    -- The files stay; they just stop belonging to accounts that are about to go.
    if exists (select 1 from information_schema.columns where table_schema = 'storage' and table_name = 'objects' and column_name = 'owner') then
      update storage.objects set owner = null where bucket_id = 'avatars' and owner is not null;
    end if;
    select count(*) into n from storage.objects where bucket_id = 'avatars';
    insert into courtly_reset_log values ('storage bucket', 'avatars kept with ' || n || ' file(s); the migration reuses it');
  end if;

  -- Tables first: their views, policies, triggers, indexes and foreign keys go with them.
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind in ('r', 'p') order by c.relname loop
    execute format('drop table if exists public.%I cascade', r.relname);
    insert into courtly_reset_log values ('table', r.relname);
  end loop;
  for r in select c.relname, c.relkind from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind in ('v', 'm') order by c.relname loop
    execute format('drop %s if exists public.%I cascade', case when r.relkind = 'm' then 'materialized view' else 'view' end, r.relname);
    insert into courtly_reset_log values ('view', r.relname);
  end loop;
  -- Functions next; the triggers on auth.users and storage.objects that call them go too.
  for r in select p.proname, p.prokind, pg_get_function_identity_arguments(p.oid) as args
           from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' order by p.proname, 3 loop
    execute format('drop %s if exists public.%I(%s) cascade',
                   case r.prokind when 'p' then 'procedure' when 'a' then 'aggregate' else 'function' end, r.proname, r.args);
    insert into courtly_reset_log values ('function', r.proname || '(' || r.args || ')');
  end loop;
  -- Then the types that stood under the columns, and any sequence left on its own.
  for r in select t.typname from pg_type t join pg_namespace s on s.oid = t.typnamespace
           where s.nspname = 'public' and t.typtype in ('e', 'd') order by t.typname loop
    execute format('drop type if exists public.%I cascade', r.typname);
    insert into courtly_reset_log values ('type', r.typname);
  end loop;
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'S' order by c.relname loop
    execute format('drop sequence if exists public.%I cascade', r.relname);
    insert into courtly_reset_log values ('sequence', r.relname);
  end loop;

  if exists (select 1 from pg_namespace where nspname = 'private') then
    drop schema private cascade;
    insert into courtly_reset_log values ('schema', 'private (migration ledger and settings)');
  end if;

  -- Accounts last, once no trigger or foreign key of ours is left to fire on them.
  delete from vault.secrets where name like 'apple-refresh-%';
  get diagnostics n = row_count;
  if n > 0 then insert into courtly_reset_log values ('vault secrets', n || ' Apple refresh tokens'); end if;
  delete from auth.users;
  get diagnostics n = row_count;
  insert into courtly_reset_log values ('auth users', n::text);
end $$;

select kind, name from courtly_reset_log order by kind, name;
