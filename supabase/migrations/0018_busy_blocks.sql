-- Players can mark blocks of the week busy. Hits in those blocks stay out of their feed, as do hits in
-- the coming week that fall on blocks their calendar says are busy.

alter table public.profiles add column if not exists busy_mask integer not null default 0;

create or replace function public.profile_json(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', p.id, 'first_name', p.first_name, 'last_name', p.last_name, 'photo_path', p.photo_path,
    'birthday', p.birthday, 'gender', p.gender, 'level', p.level, 'formats', to_jsonb(p.formats),
    'zip', p.zip, 'area_label', p.area_label,
    'home_lat', extensions.st_y(p.home_point::extensions.geometry), 'home_lng', extensions.st_x(p.home_point::extensions.geometry),
    'radius_mi', p.radius_mi, 'availability_mask', p.availability_mask, 'busy_mask', p.busy_mask, 'busy_mask_week', p.busy_mask_week,
    'calendar_provider', p.calendar_provider, 'phone_e164', p.phone_e164, 'hit_visibility', p.hit_visibility,
    'hits_played', p.hits_played, 'coach_marks_done', p.coach_marks_done,
    'onboarding_completed_at', p.onboarding_completed_at,
    'blocked_count', (select count(*) from public.blocks b where b.blocker_id = p.id)
  )
  from public.profiles p where p.id = p_user;
$$;

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
    busy_mask = case when patch ? 'busy_mask' then (patch->>'busy_mask')::int else busy_mask end,
    busy_mask_week = case when patch ? 'busy_mask_week' then (patch->>'busy_mask_week')::int else busy_mask_week end,
    calendar_provider = case when patch ? 'calendar_provider' then (patch->>'calendar_provider')::public.calendar_provider else calendar_provider end,
    phone_e164 = case when patch ? 'phone_e164' then v_phone else phone_e164 end,
    phone_hash = case when patch ? 'phone_e164' then (case when v_phone is null then null else public.contact_hash(v_phone) end) else phone_hash end,
    hit_visibility = case when patch ? 'hit_visibility' then (patch->>'hit_visibility')::public.hit_visibility else hit_visibility end,
    coach_marks_done = case when patch ? 'coach_marks_done' then (patch->>'coach_marks_done')::boolean else coach_marks_done end
  where id = v_user;

  return public.profile_json(v_user);
end $$;

-- A moment the player has marked busy: by hand for any week, or by calendar for the coming seven days.
create or replace function public.busy_at(p_user uuid, p_at timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select (p.busy_mask | case when p_at < now() + interval '7 days' then coalesce(p.busy_mask_week, 0) else 0 end) & (1 << bit) <> 0
    from public.profiles p, (select public.availability_bit(p_at) as bit) b
    where p.id = p_user and b.bit is not null
  ), false);
$$;

create or replace function public.get_play_feed() returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_user uuid := public.assert_onboarded(); me public.profiles; v_now timestamptz := now();
begin
  select * into me from public.profiles where id = v_user;

  return jsonb_build_object(
    'needs_reply', coalesce((
      select jsonb_agg(item order by ts desc) from (
        select jsonb_build_object('kind', 'join_request', 'request_id', r.id, 'player', public.player_card(r.user_id),
                                  'hit', public.hit_json(h.id, v_user), 'created_at', r.created_at) as item, r.created_at as ts
        from public.join_requests r join public.hits h on h.id = r.hit_id
        where h.host_id = v_user and r.status = 'pending' and h.status in ('open', 'confirmed') and h.starts_at > v_now
        union all
        select jsonb_build_object('kind', 'invite', 'invite_id', i.id, 'host', public.player_card(h.host_id),
                                  'hit', public.hit_json(h.id, v_user), 'created_at', i.created_at), i.created_at
        from public.hit_invites i join public.hits h on h.id = i.hit_id
        where i.target_user_id = v_user and i.status = 'open' and i.expires_at > v_now and h.status in ('open', 'confirmed')
          and h.starts_at > v_now and h.spots_open > 0
        union all
        select jsonb_build_object('kind', 'accepted', 'request_id', r.id, 'host', public.player_card(h.host_id),
                                  'hit', public.hit_json(h.id, v_user), 'created_at', r.responded_at), r.responded_at
        from public.join_requests r join public.hits h on h.id = r.hit_id
        where r.user_id = v_user and r.status = 'accepted' and r.seen_by_requester_at is null and h.status = 'confirmed' and h.starts_at > v_now
      ) x
    ), '[]'::jsonb),

    'from_friends', coalesce((
      select jsonb_agg(public.hit_json(h.id, v_user) || jsonb_build_object('reason', public.feed_reason(h.id, v_user, false)) order by h.starts_at)
      from (
        select h.* from public.hits h
        join public.profiles hp on hp.id = h.host_id
        where h.status in ('open', 'confirmed') and h.starts_at > now() and h.spots_open > 0
          and public.feed_candidate(h.id, v_user) and public.is_friend(v_user, h.host_id)
          and not public.busy_at(v_user, h.starts_at)
        order by h.starts_at limit 20
      ) h
    ), '[]'::jsonb),

    'near_you', coalesce((
      select jsonb_agg(public.hit_json(h.id, v_user) || jsonb_build_object('reason', public.feed_reason(h.id, v_user, h.rn = 1)) order by h.rn)
      from (
        select h.*, row_number() over (order by extensions.st_distance(c.point, me.home_point), h.starts_at) as rn
        from public.hits h
        join public.courts c on c.id = h.court_id
        where h.status in ('open', 'confirmed') and h.starts_at > now() and h.spots_open > 0
          and public.feed_candidate(h.id, v_user) and not public.is_friend(v_user, h.host_id)
          and not public.busy_at(v_user, h.starts_at)
          and me.home_point is not null and extensions.st_dwithin(c.point, me.home_point, me.radius_mi * 1609.344)
        order by rn limit 30
      ) h
    ), '[]'::jsonb),

    'free_this_week', coalesce((
      select jsonb_agg(public.player_card(free.other))
      from (
        select f.other
        from (
          select case when fr.user_a = v_user then fr.user_b else fr.user_a end as other
          from public.friendships fr where fr.status = 'accepted' and v_user in (fr.user_a, fr.user_b)
        ) f
        join public.profiles p on p.id = f.other
        where public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
          and (p.availability_mask & ~coalesce(p.busy_mask_week, 0) & ~p.busy_mask & public.remaining_week_mask()) <> 0
        order by p.first_name
        limit 6   -- six cards at most; the cut has to happen before the aggregate
      ) free
    ), '[]'::jsonb),

    'my_upcoming_count', (
      select count(*) from public.hits h join public.hit_players hp on hp.hit_id = h.id
      where hp.user_id = v_user and hp.left_at is null and h.status in ('open', 'confirmed') and h.starts_at > v_now
    ),
    'badge', public.badge_count(v_user)
  );
end $$;

revoke execute on function public.busy_at(uuid, timestamptz) from public, anon, authenticated;
