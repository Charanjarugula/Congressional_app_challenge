-- Courtly schema: extensions, enums, tables, indexes.
-- Reads go through row-level security (0002); writes go through the functions in 0003–0008.

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Values the database needs that are not secrets of the app's users (function URL, webhook secret).
create table if not exists private.settings (
  key text primary key,
  value text not null
);

-- Enums --------------------------------------------------------------------------

create type public.gender as enum ('man', 'woman', 'non_binary', 'prefer_not');
create type public.player_level as enum ('beginner', 'intermediate', 'advanced', 'competitive');
create type public.play_format as enum ('casual', 'singles', 'doubles', 'drills');
create type public.hit_visibility as enum ('anyone', 'friends', 'invite_only');
create type public.hit_status as enum ('open', 'confirmed', 'cancelled', 'played', 'expired');
create type public.request_status as enum ('pending', 'accepted', 'declined', 'cancelled', 'expired');
create type public.invite_status as enum ('open', 'filled', 'expired', 'cancelled');
create type public.friendship_status as enum ('pending', 'accepted');
create type public.chat_type as enum ('dm', 'group', 'hit');
create type public.message_type as enum ('text', 'hit_invite', 'system');
create type public.report_reason as enum ('no_show', 'rude_or_unsafe', 'fake_profile', 'other');
create type public.report_status as enum ('open', 'reviewed', 'actioned');
create type public.calendar_provider as enum ('none', 'apple', 'google');
create type public.court_source as enum ('seed', 'apple_maps', 'user');
create type public.player_role as enum ('host', 'player');
create type public.player_source as enum ('host', 'ask', 'invite');
create type public.notification_kind as enum (
  'join_request', 'hit_invite', 'request_accepted', 'request_declined', 'player_joined',
  'hit_cancelled', 'player_left', 'reminder_day', 'reminder_hour', 'day_after_check',
  'friend_added', 'friend_accepted', 'message', 'report'
);

-- Tables -------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key,                        -- same value as auth.users.id; no FK so deletion can anonymize
  first_name text not null default '',
  last_name text not null default '',
  photo_path text,
  birthday date,
  gender public.gender,
  level public.player_level,
  formats public.play_format[] not null default '{}',
  zip text,
  area_label text,
  home_point extensions.geography(point, 4326), -- ZIP or city centroid, never a precise location
  radius_mi smallint not null default 10 check (radius_mi in (5, 10, 15, 25)),
  availability_mask integer not null default 0 check (availability_mask between 0 and 2097151),
  busy_mask_week integer check (busy_mask_week between 0 and 2097151),
  calendar_provider public.calendar_provider not null default 'none',
  phone_e164 text,
  phone_hash text,
  email_hash text,
  hit_visibility public.hit_visibility not null default 'anyone' check (hit_visibility in ('anyone', 'friends')),
  hits_played integer not null default 0,
  no_shows integer not null default 0,
  coach_marks_done boolean not null default false,
  onboarding_completed_at timestamptz,
  suspended_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_phone_hash_idx on public.profiles (phone_hash) where phone_hash is not null;
create index profiles_email_hash_idx on public.profiles (email_hash) where email_hash is not null;
create index profiles_home_point_idx on public.profiles using gist (home_point);

create table public.courts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  city text,
  point extensions.geography(point, 4326) not null,
  surface text check (surface in ('hard', 'clay', 'grass', 'other')),
  lights boolean,
  source public.court_source not null default 'user',
  apple_place_id text,
  created_by uuid,
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index courts_point_idx on public.courts using gist (point);
create index courts_name_trgm_idx on public.courts using gin (name extensions.gin_trgm_ops);
create unique index courts_apple_place_idx on public.courts (apple_place_id) where apple_place_id is not null;

create table public.chats (
  id uuid primary key default gen_random_uuid(),
  type public.chat_type not null,
  name text,
  hit_id uuid,                                 -- FK added below, after hits
  created_by uuid,
  last_message_id uuid,                        -- FK added below, after messages
  last_message_at timestamptz,
  last_message_preview text,
  created_at timestamptz not null default now()
);

create table public.hits (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles (id),
  court_id uuid not null references public.courts (id),
  starts_at timestamptz not null,
  duration_min smallint not null check (duration_min in (60, 90, 120)),
  format public.play_format not null,
  spots_total smallint not null check (spots_total between 1 and 7),
  spots_open smallint not null check (spots_open >= 0),
  visibility public.hit_visibility not null default 'anyone',
  status public.hit_status not null default 'open',
  chat_id uuid references public.chats (id) on delete set null,
  reminder_day_sent_at timestamptz,
  reminder_hour_sent_at timestamptz,
  day_after_sent_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index hits_live_idx on public.hits (status, starts_at) where status in ('open', 'confirmed');
create index hits_host_idx on public.hits (host_id, starts_at);
create index hits_court_idx on public.hits (court_id);

alter table public.chats
  add constraint chats_hit_fk foreign key (hit_id) references public.hits (id) on delete set null;

create table public.hit_players (
  hit_id uuid not null references public.hits (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  role public.player_role not null,
  source public.player_source not null,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (hit_id, user_id)
);
create index hit_players_user_idx on public.hit_players (user_id) where left_at is null;

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  hit_id uuid not null references public.hits (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  status public.request_status not null default 'pending',
  seen_by_requester_at timestamptz,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create unique index join_requests_pending_idx on public.join_requests (hit_id, user_id) where status = 'pending';
create index join_requests_hit_idx on public.join_requests (hit_id, status);
create index join_requests_user_idx on public.join_requests (user_id, status);

create table public.chat_members (
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  last_read_at timestamptz,
  muted boolean not null default false,
  primary key (chat_id, user_id)
);
create index chat_members_user_idx on public.chat_members (user_id) where left_at is null;

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  type public.message_type not null default 'text',
  body text not null default '',
  payload jsonb not null default '{}'::jsonb,
  client_id uuid,
  created_at timestamptz not null default now()
);
create unique index messages_client_idx on public.messages (chat_id, client_id) where client_id is not null;
create index messages_page_idx on public.messages (chat_id, created_at desc, id desc);

alter table public.chats
  add constraint chats_last_message_fk foreign key (last_message_id) references public.messages (id) on delete set null;

create table public.hit_invites (
  id uuid primary key default gen_random_uuid(),
  hit_id uuid not null references public.hits (id) on delete cascade,
  chat_id uuid not null references public.chats (id) on delete cascade,
  message_id uuid references public.messages (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  target_user_id uuid references public.profiles (id),
  spots smallint not null check (spots >= 1),
  claimed smallint not null default 0,
  expires_at timestamptz not null,
  status public.invite_status not null default 'open',
  created_at timestamptz not null default now()
);
create index hit_invites_hit_idx on public.hit_invites (hit_id);
create index hit_invites_target_idx on public.hit_invites (target_user_id, status) where target_user_id is not null;
create index hit_invites_chat_idx on public.hit_invites (chat_id);
create index hit_invites_open_idx on public.hit_invites (status, expires_at) where status = 'open';

create table public.friendships (
  user_a uuid not null references public.profiles (id),
  user_b uuid not null references public.profiles (id),
  status public.friendship_status not null default 'pending',
  requested_by uuid not null,
  dm_chat_id uuid references public.chats (id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index friendships_b_idx on public.friendships (user_b);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id),
  blocked_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id),
  reported_id uuid not null references public.profiles (id),
  hit_id uuid references public.hits (id) on delete set null,
  reason public.report_reason not null,
  details text,
  also_blocked boolean not null default false,
  auto boolean not null default false,
  status public.report_status not null default 'open',
  created_at timestamptz not null default now()
);
create index reports_reported_idx on public.reports (reported_id, created_at desc);

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  app_version text,
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind public.notification_kind not null,
  title text not null,
  body text not null,
  deep_link text,
  collapse_id text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  pushed_at timestamptz,
  push_status text,
  push_attempts smallint not null default 0,
  read_at timestamptz
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unpushed_idx on public.notifications (created_at) where pushed_at is null;

create table public.attendance_checks (
  hit_id uuid not null references public.hits (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  about_user_id uuid not null references public.profiles (id),
  showed_up boolean not null,
  created_at timestamptz not null default now(),
  primary key (hit_id, user_id, about_user_id)
);

create table public.apple_tokens (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  vault_secret_id uuid not null,
  created_at timestamptz not null default now()
);

create table public.blocked_terms (
  term text primary key
);

create table public.admin_users (
  user_id uuid primary key
);

create table public.rate_limits (
  user_id uuid not null,
  action text not null,
  window_start timestamptz not null,
  count integer not null default 0,
  primary key (user_id, action, window_start)
);

-- updated_at maintenance ---------------------------------------------------------

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger hits_touch before update on public.hits for each row execute function public.touch_updated_at();

-- The keyed hash the app computes for address-book entries, so the verified sign-in email and a
-- typed phone number can be matched without the client choosing the hash.
create or replace function public.contact_hash(p_value text) returns text
language sql immutable set search_path = public, extensions as $$
  select encode(extensions.hmac(lower(btrim(p_value)), 'courtly-contacts-v1', 'sha256'), 'hex');
$$;

-- A profile row for every auth user, created the moment they sign up, with the hash of the email
-- they verified; it follows the email if it changes.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email_hash)
  values (new.id, case when new.email is null then null else public.contact_hash(new.email) end)
  on conflict (id) do update set email_hash = excluded.email_hash;
  -- The support address moderates: reports reach it from its first sign-in on.
  if new.email is not null and lower(new.email) = lower(coalesce((select value from private.settings where key = 'admin_email'), '')) then
    insert into public.admin_users (user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
create trigger on_auth_user_email_changed after update of email on auth.users for each row
  when (old.email is distinct from new.email) execute function public.handle_new_user();
