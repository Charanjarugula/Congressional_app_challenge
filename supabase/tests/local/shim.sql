-- Local stand-ins for what a Supabase project provides. Test harness only.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
$$;

create schema extensions;
create extension if not exists pg_trgm with schema extensions;
-- PostGIS stand-in: a point with lng/lat and spherical distance in metres.
create type extensions.geography as (lng float8, lat float8);
create function extensions.st_makepoint(x float8, y float8) returns extensions.geography language sql immutable as $$ select row(x, y)::extensions.geography $$;
create function extensions.st_setsrid(g extensions.geography, srid int) returns extensions.geography language sql immutable as $$ select g $$;
create function extensions.st_x(g extensions.geography) returns float8 language sql immutable as $$ select (g).lng $$;
create function extensions.st_y(g extensions.geography) returns float8 language sql immutable as $$ select (g).lat $$;
create function extensions.st_distance(a extensions.geography, b extensions.geography) returns float8 language sql immutable as $$
  select 6371000.0 * 2 * asin(sqrt(
    power(sin(radians((b).lat - (a).lat) / 2), 2)
    + cos(radians((a).lat)) * cos(radians((b).lat)) * power(sin(radians((b).lng - (a).lng) / 2), 2)))
$$;
create function extensions.st_dwithin(a extensions.geography, b extensions.geography, metres float8) returns boolean language sql immutable as $$
  select extensions.st_distance(a, b) <= metres
$$;

create schema cron;
create function cron.schedule(job text, sched text, cmd text) returns bigint language sql as $$ select 1::bigint $$;

create schema net;
create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb, headers jsonb default '{}'::jsonb, timeout_milliseconds int default 5000)
returns bigint language sql as $$ select 1::bigint $$;

create schema vault;
create table vault.secrets (id uuid primary key default gen_random_uuid(), secret text, name text, created_at timestamptz default now());
create view vault.decrypted_secrets as select id, secret as decrypted_secret, name, created_at from vault.secrets;
create function vault.create_secret(new_secret text, new_name text default null) returns uuid language sql as $$
  insert into vault.secrets (secret, name) values (new_secret, new_name) returning id
$$;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

create publication supabase_realtime;
grant usage on schema public to anon, authenticated, service_role;
