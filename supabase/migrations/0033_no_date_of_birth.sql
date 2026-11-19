-- App Review 5.1.1(v): Courtly no longer asks for, keeps or shows a date of birth. The app is rated
-- 18+ in the App Store, and where the law requires it Apple's own age range check (Declared Age Range)
-- runs on the device. Someone already marked under 18 (underage_at) stays blocked.

-- 1. Finishing onboarding no longer needs a birthday.
create or replace function public.complete_onboarding() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); p public.profiles;
begin
  select * into p from public.profiles where id = v_user;
  if p.underage_at is not null then raise exception 'underage'; end if;
  if btrim(p.first_name) = '' then raise exception 'missing_name'; end if;
  if p.level is null then raise exception 'missing_level'; end if;
  if cardinality(p.formats) = 0 then raise exception 'missing_formats'; end if;
  if p.home_point is null then raise exception 'missing_location'; end if;

  update public.profiles set onboarding_completed_at = coalesce(onboarding_completed_at, now()) where id = v_user;
  return public.profile_json(v_user);
end $$;

-- 2. Social features are closed only to someone already known to be under 18.
create or replace function private.assert_adult() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if exists (select 1 from public.profiles where id = v_user and underage_at is not null) then raise exception 'underage'; end if;
  return v_user;
end $$;
revoke execute on function private.assert_adult() from public, anon, authenticated;

-- 3. The profile guard keeps everything but the birthday rule.
create or replace function private.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.photo_path is distinct from old.photo_path and new.photo_path is not null
     and new.photo_path !~ ('^' || new.id::text || '/[A-Za-z0-9_-]+\.(jpg|png)$') then
    raise exception 'invalid_photo';
  end if;
  if new.first_name is distinct from old.first_name or new.last_name is distinct from old.last_name
     or new.area_label is distinct from old.area_label then
    if length(new.first_name) > 40 or length(new.last_name) > 40 or length(new.area_label) > 80 then
      raise exception 'too_long';
    end if;
    perform public.filter_text(concat_ws(' ', new.first_name, new.last_name, new.area_label));
  end if;
  if length(new.zip) > 10 then raise exception 'too_long'; end if;
  if new.home_point is distinct from old.home_point and auth.uid() = new.id and old.home_point is not null then
    perform public.check_rate_limit('home_area', 10, interval '1 day');
  end if;
  return new;
end $$;

-- 4. A birthday is never stored again, whoever writes the row (an older app version included).
create or replace function private.profiles_no_birthday() returns trigger
language plpgsql set search_path = public as $$
begin
  new.birthday := null;
  return new;
end $$;
drop trigger if exists profiles_no_birthday on public.profiles;
create trigger profiles_no_birthday before insert or update on public.profiles
  for each row execute function private.profiles_no_birthday();
comment on column public.profiles.birthday is 'Unused since 0033: always null. Courtly does not collect a date of birth.';

-- 5. The profile no longer takes or returns a birthday.
CREATE OR REPLACE FUNCTION public.update_profile(patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_user uuid := public.assert_signed_in(); v_phone text;
begin
  if patch ? 'radius_mi' and (patch->>'radius_mi')::int not in (5, 10, 15, 25) then raise exception 'invalid_radius'; end if;
  if patch ? 'hit_visibility' and patch->>'hit_visibility' not in ('anyone', 'friends') then raise exception 'invalid_visibility'; end if;

  update public.profiles set
    first_name = case when patch ? 'first_name' then left(btrim(patch->>'first_name'), 40) else first_name end,
    last_name = case when patch ? 'last_name' then left(btrim(patch->>'last_name'), 40) else last_name end,
    photo_path = case when patch ? 'photo_path' then patch->>'photo_path' else photo_path end,
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
    busy_mask = case when patch ? 'busy_mask' then (patch->>'busy_mask')::int else busy_mask end,
    busy_mask_week = case when patch ? 'busy_mask_week' then (patch->>'busy_mask_week')::int else busy_mask_week end,
    calendar_provider = case when patch ? 'calendar_provider' then (patch->>'calendar_provider')::public.calendar_provider else calendar_provider end,
    -- the app sends the iPhone's zone; one Postgres doesn't know keeps the last good one instead of failing onboarding
    time_zone = case when private.valid_time_zone(patch->>'time_zone') then patch->>'time_zone' else time_zone end,
    phone_e164 = null,   -- no longer collected (2. below)
    phone_hash = null,
    hit_visibility = case when patch ? 'hit_visibility' then (patch->>'hit_visibility')::public.hit_visibility else hit_visibility end,
    coach_marks_done = case when patch ? 'coach_marks_done' then (patch->>'coach_marks_done')::boolean else coach_marks_done end
  where id = v_user;

  return public.profile_json(v_user);
end $function$;

create or replace function public.profile_json(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', p.id, 'first_name', p.first_name, 'last_name', p.last_name, 'photo_path', p.photo_path,
    'gender', p.gender, 'level', p.level, 'formats', to_jsonb(p.formats),
    'zip', p.zip, 'area_label', p.area_label,
    'home_lat', extensions.st_y(p.home_point::extensions.geometry), 'home_lng', extensions.st_x(p.home_point::extensions.geometry),
    'radius_mi', p.radius_mi, 'availability_mask', p.availability_mask, 'busy_mask', p.busy_mask, 'busy_mask_week', p.busy_mask_week,
    'calendar_provider', p.calendar_provider, 'phone_e164', p.phone_e164, 'hit_visibility', p.hit_visibility,
    'hits_played', p.hits_played, 'time_zone', p.time_zone, 'coach_marks_done', p.coach_marks_done,
    'onboarding_completed_at', p.onboarding_completed_at,
    'blocked_count', (select count(*) from public.blocks b where b.blocker_id = p.id)
  )
  from public.profiles p where p.id = p_user;
$$;

-- 6. Every birthday already stored is erased.
update public.profiles set birthday = null where birthday is not null;
