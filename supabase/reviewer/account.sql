-- The App Review account: reviewer@courtly.app with the password in the courtly.reviewer_password
-- setting (the deploy step passes REVIEWER_PASSWORD, an eight-digit code the reviewer types where
-- the app asks for the email code), onboarded in Wellington. Creates it or resets the password.
do $$
declare v_pw text := nullif(current_setting('courtly.reviewer_password', true), ''); v_id uuid; v_email text := 'reviewer@courtly.app';
begin
  if v_pw is null then raise exception 'reviewer password missing'; end if;
  select id into v_id from auth.users where email = v_email;
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data,
                            raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change, is_sso_user)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
            extensions.crypt(v_pw, extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}'::jsonb,
            '{}'::jsonb, now(), now(), '', '', '', '', false);
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
  else
    update auth.users set encrypted_password = extensions.crypt(v_pw, extensions.gen_salt('bf')), updated_at = now() where id = v_id;
  end if;
  update public.profiles set first_name = 'App', last_name = 'Reviewer', birthday = '1990-01-01', level = 'intermediate', formats = '{casual}',
    zip = '33414', area_label = 'Wellington, FL',
    home_point = extensions.st_setsrid(extensions.st_makepoint(-80.2416, 26.6618), 4326)::extensions.geography,
    radius_mi = 15, availability_mask = 2097151, onboarding_completed_at = coalesce(onboarding_completed_at, now()), coach_marks_done = true
  where id = v_id;
  if not found then raise exception 'no profile row for %', v_email; end if;
end $$;
