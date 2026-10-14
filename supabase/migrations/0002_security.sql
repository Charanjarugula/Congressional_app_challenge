-- Helper predicates, row-level security, the public player view, storage, realtime.
-- Helpers are security definer so policies never recurse into other policies.

create or replace function public.is_active_user(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.onboarding_completed_at is not null and p.suspended_at is null and p.deleted_at is null
  );
$$;

create or replace function public.is_friend(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a is not null and b is not null and exists (
    select 1 from public.friendships f
    where f.user_a = least(a, b) and f.user_b = greatest(a, b) and f.status = 'accepted'
  );
$$;

create or replace function public.is_blocked_either(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

create or replace function public.host_allows_anyone(host uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = host and hit_visibility = 'anyone');
$$;

create or replace function public.is_chat_member(p_chat uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_members where chat_id = p_chat and user_id = p_user and left_at is null
  );
$$;

create or replace function public.is_hit_host(p_hit uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.hits where id = p_hit and host_id = p_user);
$$;

create or replace function public.is_hit_member(p_hit uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_hit_host(p_hit, p_user) or exists (
    select 1 from public.hit_players where hit_id = p_hit and user_id = p_user and left_at is null
  );
$$;

create or replace function public.has_invite_access(p_hit uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hit_invites i
    where i.hit_id = p_hit and i.status = 'open'
      and (i.target_user_id = p_user or public.is_chat_member(i.chat_id, p_user))
  );
$$;

create or replace function public.can_see_hit(p_hit uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h
    where h.id = p_hit and (
      h.host_id = p_user
      or public.is_hit_member(p_hit, p_user)
      or (
        h.status in ('open', 'confirmed') and h.starts_at > now()   -- strangers only ever see live hits
        and not public.is_blocked_either(p_user, h.host_id)
        and public.is_active_user(h.host_id)
        and (
          (h.visibility = 'anyone' and public.host_allows_anyone(h.host_id))
          or (h.visibility in ('anyone', 'friends') and public.is_friend(p_user, h.host_id))
          or public.has_invite_access(p_hit, p_user)
        )
      )
    )
  );
$$;

-- Row-level security --------------------------------------------------------------
-- Tables without a policy for an operation refuse it; writes happen in security definer functions.

alter table public.profiles enable row level security;
alter table public.courts enable row level security;
alter table public.hits enable row level security;
alter table public.hit_players enable row level security;
alter table public.join_requests enable row level security;
alter table public.hit_invites enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
alter table public.attendance_checks enable row level security;
alter table public.apple_tokens enable row level security;
alter table public.blocked_terms enable row level security;
alter table public.admin_users enable row level security;
alter table public.rate_limits enable row level security;

create policy profiles_select_own on public.profiles for select to authenticated using (id = auth.uid());
create policy courts_select on public.courts for select to authenticated using (hidden = false);
create policy hits_select on public.hits for select to authenticated using (public.can_see_hit(id));
create policy hit_players_select on public.hit_players for select to authenticated using (public.can_see_hit(hit_id));
create policy join_requests_select on public.join_requests for select to authenticated
  using (user_id = auth.uid() or public.is_hit_host(hit_id));
create policy hit_invites_select on public.hit_invites for select to authenticated
  using (target_user_id = auth.uid() or public.is_chat_member(chat_id) or public.is_hit_host(hit_id));
create policy friendships_select on public.friendships for select to authenticated
  using (auth.uid() in (user_a, user_b));
create policy blocks_select on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy chats_select on public.chats for select to authenticated using (public.is_chat_member(id));
create policy chat_members_select on public.chat_members for select to authenticated using (public.is_chat_member(chat_id));
create policy messages_select on public.messages for select to authenticated
  using (public.is_chat_member(chat_id) and (sender_id is null or not public.is_blocked_either(auth.uid(), sender_id)));
create policy device_tokens_all on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy attendance_select on public.attendance_checks for select to authenticated using (user_id = auth.uid());

-- Grants are explicit so they do not depend on the project's "automatically expose tables" setting.
grant usage on schema public to authenticated, service_role;
grant select on public.profiles, public.courts, public.hits, public.hit_players, public.join_requests,
  public.hit_invites, public.friendships, public.blocks, public.chats, public.chat_members, public.messages,
  public.notifications, public.attendance_checks to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant update on public.notifications to authenticated;
grant all on all tables in schema public to service_role;

-- The anon key never reads application data; the app always has a signed-in user.
revoke all on all tables in schema public from anon;
revoke all on public.apple_tokens, public.admin_users, public.rate_limits, public.reports, public.blocked_terms from authenticated;

-- What other players may see of a profile ------------------------------------------

create or replace view public.player_cards with (security_invoker = false) as
  select p.id, p.first_name, left(p.last_name, 1) as last_initial, p.photo_path, p.level, p.formats,
         p.area_label, p.hits_played, p.availability_mask, p.busy_mask_week
  from public.profiles p
  where auth.uid() is not null
    and public.is_active_user(auth.uid())
    and p.onboarding_completed_at is not null
    and p.suspended_at is null and p.deleted_at is null
    and not public.is_blocked_either(auth.uid(), p.id);

revoke all on public.player_cards from anon;
grant select on public.player_cards to authenticated;

-- Storage: public avatars, each user writes only under their own folder --------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy avatars_public_read on storage.objects for select using (bucket_id = 'avatars');
create policy avatars_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update_own on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Realtime: the inbox listens to chats, an open thread to messages and invite cards ------

do $$
declare t text;
begin
  foreach t in array array['messages', 'chats', 'hit_invites'] loop
    if not exists (
      select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
