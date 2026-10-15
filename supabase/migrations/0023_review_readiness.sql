-- Search, contacts, photos and profile edits tightened before App Review.
--
-- Demo accounts stay out of name search and contact matching for real players too, so a real player
-- can't find "Ana" or "Priya" and befriend someone who isn't a person. Same rule as the feed and
-- suggestions in 0022: hidden from real players; demo and App Review accounts still see everyone.
--
-- Contact matches also say where each person stands with you (friend, requested, requested_me), like
-- search does, so the app never offers Add for someone you've already asked.

create or replace function public.search_players(p_query text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); v_q text := btrim(coalesce(p_query, ''));
begin
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((
    select jsonb_agg(public.player_card(p.id) || jsonb_build_object(
      'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, p.id)),
      'relationship', public.relationship_to(v_user, p.id)
    ) order by p.first_name, p.last_name)
    from (
      select p.* from public.profiles p
      where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
        and not private.hidden_demo(v_user, p.id)
        -- First name, or first name and last initial: never more of the surname than other players see.
        and (p.first_name ilike v_q || '%' or (p.first_name || ' ' || left(p.last_name, 1)) ilike v_q || '%')
      order by p.first_name, p.last_name limit 20
    ) p
  ), '[]'::jsonb);
end $$;

create or replace function public.match_contacts(p_hashes text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if cardinality(p_hashes) > 5000 then raise exception 'too_many_hashes'; end if;
  perform public.check_rate_limit('match_contacts', 30, interval '1 day');   -- Add friends re-checks on each visit
  return coalesce((
    select jsonb_agg(jsonb_build_object('hash', h.hash, 'player', public.player_card(p.id),
                                        'relationship', public.relationship_to(v_user, p.id)))
    from unnest(p_hashes) as h(hash)
    join public.profiles p on (p.phone_hash = h.hash or p.email_hash = h.hash)
    where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
      and not private.hidden_demo(v_user, p.id)
  ), '[]'::jsonb);
end $$;

-- Profile photos: the bucket is public, so photos load by URL without any read rule. Listing the
-- bucket (every player's folder) is no longer open to anyone; a player can only list their own
-- folder, which an upload that replaces a file needs.
drop policy if exists avatars_public_read on storage.objects;
create policy avatars_read_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- A profile can only point at a photo in its own folder, and a birthday changed after onboarding
-- still has to be 18 or more years ago.
create or replace function private.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.photo_path is distinct from old.photo_path and new.photo_path is not null
     and new.photo_path not like new.id::text || '/%' then
    raise exception 'invalid_photo';
  end if;
  if new.birthday is distinct from old.birthday and new.onboarding_completed_at is not null
     and new.birthday > (current_date - interval '18 years') then
    raise exception 'underage';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update of photo_path, birthday on public.profiles
  for each row execute function private.profiles_guard();

-- A hit the host already said no to stays out of that player's feed; asking again would only fail.
create or replace function public.feed_candidate(p_hit uuid, p_viewer uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h join public.profiles hp on hp.id = h.host_id
    where h.id = p_hit and h.status in ('open', 'confirmed') and h.spots_open > 0 and h.starts_at > now()
      and h.host_id <> p_viewer and h.visibility <> 'invite_only'
      and hp.suspended_at is null and hp.deleted_at is null and hp.onboarding_completed_at is not null
      and not public.is_blocked_either(p_viewer, h.host_id)
      and not private.hidden_demo(p_viewer, h.host_id)
      and not exists (select 1 from public.hit_players p where p.hit_id = h.id and p.user_id = p_viewer and p.left_at is null)
      and not exists (select 1 from public.join_requests r where r.hit_id = h.id and r.user_id = p_viewer and r.status in ('pending', 'declined'))
      and ((h.visibility = 'anyone' and hp.hit_visibility = 'anyone') or (h.visibility in ('anyone', 'friends') and public.is_friend(p_viewer, h.host_id)))
  );
$$;

-- The hit as the viewer sees it, now with the day-after answers the viewer already gave and where the
-- viewer stands with each other person in the hit: answers survive leaving and coming back, and the
-- hit screen never offers Add for a friend or someone already asked.
create or replace function public.hit_json(p_hit uuid, p_viewer uuid default auth.uid()) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', h.id,
    'host', public.player_card(h.host_id),
    'court', public.court_json(h.court_id),
    'starts_at', h.starts_at,
    'duration_min', h.duration_min,
    'format', h.format,
    'spots_total', h.spots_total,
    'spots_open', h.spots_open,
    'visibility', h.visibility,
    'status', h.status,
    'chat_id', h.chat_id,
    'needs_attendance', case when h.status = 'played' then public.needs_attendance(h.id, p_viewer) else false end,
    'players', coalesce((
      select jsonb_agg(public.player_card(hp.user_id) || jsonb_build_object('role', hp.role) order by hp.joined_at)
      from public.hit_players hp where hp.hit_id = h.id and hp.left_at is null and hp.role = 'player'
    ), '[]'::jsonb),
    'miles', (
      select round((extensions.st_distance(c.point, p.home_point) / 1609.344)::numeric, 1)
      from public.courts c, public.profiles p where c.id = h.court_id and p.id = p_viewer
    ),
    'pending_request_count', case when h.host_id = p_viewer
      then (select count(*) from public.join_requests r where r.hit_id = h.id and r.status = 'pending') else 0 end,
    'unread_messages', (
      select count(*) from public.messages m
      join public.chat_members cm on cm.chat_id = m.chat_id and cm.user_id = p_viewer
      where m.chat_id = h.chat_id and m.sender_id is distinct from p_viewer
        and m.created_at > coalesce(cm.last_read_at, '-infinity'::timestamptz)
    ),
    'viewer', jsonb_build_object(
      'is_host', h.host_id = p_viewer,
      'is_player', exists (select 1 from public.hit_players hp where hp.hit_id = h.id and hp.user_id = p_viewer and hp.left_at is null),
      'request', (
        select jsonb_build_object('id', r.id, 'status', r.status, 'seen', r.seen_by_requester_at is not null)
        from public.join_requests r where r.hit_id = h.id and r.user_id = p_viewer order by r.created_at desc limit 1
      ),
      'invite', (
        select jsonb_build_object('id', i.id, 'status', i.status, 'expires_at', i.expires_at)
        from public.hit_invites i where i.hit_id = h.id and i.target_user_id = p_viewer and i.status = 'open'
        order by i.created_at desc limit 1
      ),
      'attendance', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', a.about_user_id, 'showed_up', a.showed_up))
        from public.attendance_checks a where a.hit_id = h.id and a.user_id = p_viewer
      ), '[]'::jsonb),
      'relationships', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', x.uid, 'relationship', public.relationship_to(p_viewer, x.uid)))
        from (
          select h.host_id as uid
          union
          select hp.user_id from public.hit_players hp where hp.hit_id = h.id and hp.left_at is null
        ) x
        where p_viewer is not null and x.uid <> p_viewer
      ), '[]'::jsonb)
    )
  )
  from public.hits h where h.id = p_hit;
$$;


-- Calendar busy times are a snapshot of the coming week, so they count only while fresh: older than
-- 7 days, they hide nothing. The app saves a new snapshot each time it opens (save_busy_week).
alter table public.profiles add column if not exists busy_mask_week_at timestamptz;
update public.profiles set busy_mask_week_at = now() where busy_mask_week is not null and busy_mask_week_at is null;

create or replace function private.profiles_busy_stamp() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.busy_mask_week is distinct from old.busy_mask_week then
    new.busy_mask_week_at := case when new.busy_mask_week is null then null else now() end;
  end if;
  return new;
end $$;
drop trigger if exists profiles_busy_stamp on public.profiles;
create trigger profiles_busy_stamp before update of busy_mask_week on public.profiles
  for each row execute function private.profiles_busy_stamp();

create or replace function public.save_busy_week(p_mask integer) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if p_mask is null or p_mask < 0 or p_mask > 2097151 then raise exception 'invalid_mask'; end if;
  update public.profiles set busy_mask_week = p_mask, busy_mask_week_at = now() where id = v_user;
end $$;

create or replace function public.busy_at(p_user uuid, p_at timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select (p.busy_mask
            | case when p_at < now() + interval '7 days' and p.busy_mask_week_at > now() - interval '7 days'
                   then coalesce(p.busy_mask_week, 0) else 0 end) & (1 << bit) <> 0
    from public.profiles p, (select public.availability_bit(p_at) as bit) b
    where p.id = p_user and b.bit is not null
  ), false);
$$;

revoke execute on function public.save_busy_week(integer) from public, anon;
grant execute on function public.save_busy_week(integer) to authenticated;
