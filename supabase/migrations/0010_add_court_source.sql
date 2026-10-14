-- add_court failed on every court that was not already in the table: the source expression came out as text
-- and the column is the court_source enum. The smoke test now adds a new court, so this stays caught.

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
            (case when p_apple_place_id is null then 'user' else 'apple_maps' end)::public.court_source, p_apple_place_id, v_user)
    returning id into v_id;
  elsif p_apple_place_id is not null then
    update public.courts set apple_place_id = coalesce(apple_place_id, p_apple_place_id) where id = v_id;
  end if;
  return public.court_json(v_id);
end $$;
