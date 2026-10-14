-- Profile, device, court and people-lookup functions.
-- Every function here runs as the owner and checks auth.uid() itself.

create or replace function private.setting(p_key text) returns text
language sql stable security definer set search_path = private as $$
  select value from private.settings where key = p_key;
$$;

-- Signed in, not suspended, not deleted. Onboarding may still be in progress.
create or replace function public.assert_signed_in() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := auth.uid(); v_profile public.profiles;
begin
  if v_user is null then raise exception 'not_signed_in'; end if;
  select * into v_profile from public.profiles where id = v_user;
  if not found then raise exception 'no_profile'; end if;
  if v_profile.suspended_at is not null then raise exception 'account_suspended'; end if;
  if v_profile.deleted_at is not null then raise exception 'account_deleted'; end if;
  return v_user;
end $$;

-- Everything social also needs a finished profile.
create or replace function public.assert_onboarded() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if not exists (select 1 from public.profiles where id = v_user and onboarding_completed_at is not null) then
    raise exception 'onboarding_incomplete';
  end if;
  return v_user;
end $$;

-- Fixed-window counters: 30 messages a minute, 10 contact matches a day, and so on.
create or replace function public.check_rate_limit(p_action text, p_max integer, p_window interval) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := auth.uid(); v_start timestamptz; v_count integer;
begin
  v_start := case when p_window >= interval '1 day' then date_trunc('day', now()) else date_trunc('minute', now()) end;
  insert into public.rate_limits (user_id, action, window_start, count) values (v_user, p_action, v_start, 1)
  on conflict (user_id, action, window_start) do update set count = public.rate_limits.count + 1
  returning count into v_count;
  if v_count > p_max then raise exception 'rate_limited'; end if;
end $$;

-- Shapes --------------------------------------------------------------------------

create or replace function public.player_card(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'first_name', p.first_name,
    'last_initial', left(p.last_name, 1),
    'photo_path', p.photo_path,
    'level', p.level,
    'area_label', p.area_label,
    'hits_played', p.hits_played,
    'formats', to_jsonb(p.formats),
    'availability_mask', p.availability_mask,
    'busy_mask_week', p.busy_mask_week
  )
  from public.profiles p where p.id = p_user;
$$;

create or replace function public.court_json(p_court uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'address', c.address, 'city', c.city,
    'lat', extensions.st_y(c.point::extensions.geometry), 'lng', extensions.st_x(c.point::extensions.geometry),
    'surface', c.surface, 'lights', c.lights
  )
  from public.courts c where c.id = p_court;
$$;

create or replace function public.profile_json(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', p.id, 'first_name', p.first_name, 'last_name', p.last_name, 'photo_path', p.photo_path,
    'birthday', p.birthday, 'gender', p.gender, 'level', p.level, 'formats', to_jsonb(p.formats),
    'zip', p.zip, 'area_label', p.area_label,
    'home_lat', extensions.st_y(p.home_point::extensions.geometry), 'home_lng', extensions.st_x(p.home_point::extensions.geometry),
    'radius_mi', p.radius_mi, 'availability_mask', p.availability_mask, 'busy_mask_week', p.busy_mask_week,
    'calendar_provider', p.calendar_provider, 'phone_e164', p.phone_e164, 'hit_visibility', p.hit_visibility,
    'hits_played', p.hits_played, 'coach_marks_done', p.coach_marks_done,
    'onboarding_completed_at', p.onboarding_completed_at,
    'blocked_count', (select count(*) from public.blocks b where b.blocker_id = p.id)
  )
  from public.profiles p where p.id = p_user;
$$;

-- Profile ---------------------------------------------------------------------------

create or replace function public.get_me() returns jsonb
language sql stable security definer set search_path = public as $$
  select public.profile_json(public.assert_signed_in());
$$;

-- Partial update. Only the keys present in the patch change.
create or replace function public.update_profile(patch jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_signed_in(); v_phone text;
begin
  if patch ? 'phone_e164' then
    v_phone := nullif(btrim(coalesce(patch->>'phone_e164', '')), '');
    if v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'invalid_phone'; end if;
  end if;
  if patch ? 'radius_mi' and (patch->>'radius_mi')::int not in (5, 10, 15, 25) then raise exception 'invalid_radius'; end if;
  if patch ? 'hit_visibility' and patch->>'hit_visibility' not in ('anyone', 'friends') then raise exception 'invalid_visibility'; end if;

  update public.profiles set
    first_name = case when patch ? 'first_name' then left(btrim(patch->>'first_name'), 40) else first_name end,
    last_name = case when patch ? 'last_name' then left(btrim(patch->>'last_name'), 40) else last_name end,
    photo_path = case when patch ? 'photo_path' then patch->>'photo_path' else photo_path end,
    birthday = case when patch ? 'birthday' then (patch->>'birthday')::date else birthday end,
    gender = case when patch ? 'gender' then (patch->>'gender')::public.gender else gender end,
    level = case when patch ? 'level' then (patch->>'level')::public.player_level else level end,
    formats = case when patch ? 'formats'
      then (select coalesce(array_agg(value::public.play_format), '{}') from jsonb_array_elements_text(patch->'formats'))
      else formats end,
    zip = case when patch ? 'zip' then patch->>'zip' else zip end,
    area_label = case when patch ? 'area_label' then patch->>'area_label' else area_label end,
    home_point = case when patch ? 'home_lat' and patch ? 'home_lng'
      then extensions.st_setsrid(extensions.st_makepoint((patch->>'home_lng')::float8, (patch->>'home_lat')::float8), 4326)::extensions.geography
      else home_point end,
    radius_mi = case when patch ? 'radius_mi' then (patch->>'radius_mi')::smallint else radius_mi end,
    availability_mask = case when patch ? 'availability_mask' then (patch->>'availability_mask')::int else availability_mask end,
    busy_mask_week = case when patch ? 'busy_mask_week' then (patch->>'busy_mask_week')::int else busy_mask_week end,
    calendar_provider = case when patch ? 'calendar_provider' then (patch->>'calendar_provider')::public.calendar_provider else calendar_provider end,
    phone_e164 = case when patch ? 'phone_e164' then v_phone else phone_e164 end,
    phone_hash = case when patch ? 'phone_e164' then (case when v_phone is null then null else public.contact_hash(v_phone) end) else phone_hash end,
    hit_visibility = case when patch ? 'hit_visibility' then (patch->>'hit_visibility')::public.hit_visibility else hit_visibility end,
    coach_marks_done = case when patch ? 'coach_marks_done' then (patch->>'coach_marks_done')::boolean else coach_marks_done end
  where id = v_user;

  return public.profile_json(v_user);
end $$;

-- Marks onboarding finished once the required answers exist. Players must be 13 or older.
create or replace function public.complete_onboarding() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); p public.profiles;
begin
  select * into p from public.profiles where id = v_user;
  if btrim(p.first_name) = '' then raise exception 'missing_name'; end if;
  if p.birthday is null then raise exception 'missing_birthday'; end if;
  if p.birthday > (current_date - interval '13 years') then raise exception 'underage'; end if;
  if p.level is null then raise exception 'missing_level'; end if;
  if cardinality(p.formats) = 0 then raise exception 'missing_formats'; end if;
  if p.home_point is null then raise exception 'missing_location'; end if;

  update public.profiles set onboarding_completed_at = coalesce(onboarding_completed_at, now()) where id = v_user;
  return public.profile_json(v_user);
end $$;

-- Devices -----------------------------------------------------------------------------

create or replace function public.register_device(p_token text, p_environment text, p_app_version text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  insert into public.device_tokens (token, user_id, environment, app_version, updated_at)
  values (p_token, v_user, p_environment, p_app_version, now())
  on conflict (token) do update set user_id = excluded.user_id, environment = excluded.environment,
    app_version = excluded.app_version, updated_at = now();
end $$;

create or replace function public.unregister_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
end $$;

-- Courts --------------------------------------------------------------------------------

-- Reuses an existing court with the same Apple place id, or one within 100 m with a similar name.
create or replace function public.add_court(
  p_name text, p_address text, p_city text, p_lat float8, p_lng float8,
  p_apple_place_id text default null, p_surface text default null, p_lights boolean default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_onboarded(); v_point extensions.geography; v_id uuid;
begin
  if btrim(coalesce(p_name, '')) = '' then raise exception 'missing_name'; end if;
  perform public.check_rate_limit('add_court', 20, interval '1 day');
  v_point := extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;

  if p_apple_place_id is not null then
    select id into v_id from public.courts where apple_place_id = p_apple_place_id;
  end if;
  if v_id is null then
    select id into v_id from public.courts c
    where extensions.st_dwithin(c.point, v_point, 100) and extensions.similarity(lower(c.name), lower(p_name)) > 0.4
    order by extensions.st_distance(c.point, v_point) limit 1;
  end if;
  if v_id is null then
    insert into public.courts (name, address, city, point, surface, lights, source, apple_place_id, created_by)
    values (left(btrim(p_name), 80), p_address, p_city, v_point, p_surface, p_lights,
            case when p_apple_place_id is null then 'user' else 'apple_maps' end, p_apple_place_id, v_user)
    returning id into v_id;
  elsif p_apple_place_id is not null then
    update public.courts set apple_place_id = coalesce(apple_place_id, p_apple_place_id) where id = v_id;
  end if;
  return public.court_json(v_id);
end $$;

-- Courts near the caller: played-at first, then by distance.
create or replace function public.get_nearby_courts(p_limit integer default 30) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  with me as (select home_point from public.profiles where id = public.assert_signed_in())
  select coalesce(jsonb_agg(public.court_json(c.id) || jsonb_build_object(
           'miles', round((extensions.st_distance(c.point, me.home_point) / 1609.344)::numeric, 1),
           'played_count', (select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
                            where h.court_id = c.id and hp.user_id = auth.uid() and h.status = 'played')
         ) order by (select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
                     where h.court_id = c.id and hp.user_id = auth.uid() and h.status = 'played') desc,
                    extensions.st_distance(c.point, me.home_point)), '[]'::jsonb)
  from (select * from public.courts c, me
        where c.hidden = false and me.home_point is not null
        order by extensions.st_distance(c.point, me.home_point) limit p_limit) c, me;
$$;

-- People ----------------------------------------------------------------------------------

-- Hashed phone numbers and emails in, matching player cards out. Nothing from the list is stored.
create or replace function public.match_contacts(p_hashes text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if cardinality(p_hashes) > 5000 then raise exception 'too_many_hashes'; end if;
  perform public.check_rate_limit('match_contacts', 10, interval '1 day');
  return coalesce((
    select jsonb_agg(jsonb_build_object('hash', h.hash, 'player', public.player_card(p.id)))
    from unnest(p_hashes) as h(hash)
    join public.profiles p on (p.phone_hash = h.hash or p.email_hash = h.hash)
    where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
  ), '[]'::jsonb);
end $$;

create or replace function public.mutual_friend_names(p_user uuid, p_other uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.first_name order by p.first_name), '{}')
  from public.profiles p
  where p.id <> p_user and p.id <> p_other
    and public.is_friend(p_user, p.id) and public.is_friend(p_other, p.id);
$$;

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
        and (p.first_name ilike v_q || '%' or (p.first_name || ' ' || p.last_name) ilike v_q || '%')
      order by p.first_name, p.last_name limit 20
    ) p
  ), '[]'::jsonb);
end $$;

create or replace function public.relationship_to(p_user uuid, p_other uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.is_blocked_either(p_user, p_other) then 'blocked'
    when f.status = 'accepted' then 'friend'
    when f.status = 'pending' and f.requested_by = p_user then 'requested'
    when f.status = 'pending' then 'requested_me'
    else 'none' end
  from (select 1) x
  left join public.friendships f on f.user_a = least(p_user, p_other) and f.user_b = greatest(p_user, p_other);
$$;

-- Player profile screen: card, mutual friends, availability, relationship, their open hits I can see.
create or replace function public.get_player(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_signed_in(); f public.friendships;
begin
  if not public.is_active_user(p_user) or public.is_blocked_either(v_user, p_user) then raise exception 'player_unavailable'; end if;
  select * into f from public.friendships where user_a = least(v_user, p_user) and user_b = greatest(v_user, p_user);
  return public.player_card(p_user) || jsonb_build_object(
    'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, p_user)),
    'relationship', public.relationship_to(v_user, p_user),
    'dm_chat_id', f.dm_chat_id,
    'hits_together', (select count(*) from public.hit_players a join public.hit_players b on a.hit_id = b.hit_id
                      join public.hits h on h.id = a.hit_id
                      where a.user_id = v_user and b.user_id = p_user and h.status = 'played'),
    'open_hits', coalesce((
      select jsonb_agg(public.hit_json(h.id, v_user) order by h.starts_at)
      from public.hits h
      where h.host_id = p_user and h.status in ('open', 'confirmed') and h.spots_open > 0
        and h.starts_at > now() and public.can_see_hit(h.id, v_user)
    ), '[]'::jsonb)
  );
end $$;
