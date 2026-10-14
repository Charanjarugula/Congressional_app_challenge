-- The four demo players: a sign-in each, then a profile as if they had finished onboarding. A new
-- sign-in gets the password in the courtly.demo_password setting (the deploy step passes
-- DEMO_PASSWORD), or one nobody knows when there is none; an existing sign-in changes its password
-- only when one is given.
do $$
declare v_pw text := nullif(current_setting('courtly.demo_password', true), ''); e record; v_id uuid;
begin
  for e in select * from (values
    ('demo.ana@courtly.app',    'Ana',    'Ruiz',    date '1994-05-12', 'woman'::public.gender, 'intermediate'::public.player_level,
     '{casual,singles}'::public.play_format[], '33414', 'Wellington, FL',         -80.2416, 26.6618, 10, (1<<2)|(1<<11)|(1<<15)|(1<<16)|(1<<18)|(1<<19)),
    ('demo.luis@courtly.app',   'Luis',   'Morales', date '1990-09-03', 'man',   'advanced',
     '{drills,doubles}',  '33411', 'Royal Palm Beach, FL',   -80.2284, 26.7084, 15, (1<<0)|(1<<9)|(1<<15)|(1<<17)|(1<<18)),
    ('demo.priya@courtly.app',  'Priya',  'Shah',    date '1997-11-20', 'woman', 'intermediate',
     '{singles,casual}',  '33433', 'Boca Raton, FL',         -80.1570, 26.3480, 15, (1<<1)|(1<<5)|(1<<8)|(1<<15)|(1<<16)|(1<<18)),
    ('demo.marcus@courtly.app', 'Marcus', 'Lee',     date '1988-02-27', 'man',   'advanced',
     '{doubles,casual}',  '33410', 'Palm Beach Gardens, FL', -80.1172, 26.8234, 15, (1<<2)|(1<<8)|(1<<14)|(1<<15)|(1<<17)|(1<<19))
  ) as t(email, first_name, last_name, birthday, gender, level, formats, zip, area_label, lng, lat, radius_mi, mask) loop
    select id into v_id from auth.users where email = e.email;
    if v_id is null then
      v_id := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                              created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change, is_sso_user)
      values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', e.email,
              extensions.crypt(coalesce(v_pw, encode(extensions.gen_random_bytes(24), 'hex')), extensions.gen_salt('bf')), now(),
              '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '', false);
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', e.email, 'email_verified', true), 'email', now(), now(), now());
    elsif v_pw is not null then
      update auth.users set encrypted_password = extensions.crypt(v_pw, extensions.gen_salt('bf')), updated_at = now() where id = v_id;
    end if;
    -- The sign-up trigger made the profile row; this fills it in.
    update public.profiles set first_name = e.first_name, last_name = e.last_name, birthday = e.birthday, gender = e.gender, level = e.level,
      formats = e.formats, zip = e.zip, area_label = e.area_label,
      home_point = extensions.st_setsrid(extensions.st_makepoint(e.lng, e.lat), 4326)::extensions.geography,
      radius_mi = e.radius_mi, availability_mask = e.mask, hit_visibility = 'anyone', busy_mask_week = null,
      onboarding_completed_at = coalesce(onboarding_completed_at, now()), coach_marks_done = true, suspended_at = null, deleted_at = null
    where id = v_id;
    if not found then raise exception 'no profile row for %', e.email; end if;
  end loop;
end $$;
