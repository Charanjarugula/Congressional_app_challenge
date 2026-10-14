-- End-to-end smoke test run against the dev project after each deploy.
-- Everything happens inside one DO block that ends by raising SMOKE_OK, which rolls the whole thing back.
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  v_court uuid; v_hit jsonb; v_hit_id uuid; v_req jsonb; v_req_id uuid; v_chat uuid; v_msg jsonb;
  v_feed jsonb; v_inbox jsonb; v_friend jsonb; v_invite jsonb; v_group jsonb; v_n integer;
begin
  -- Three players, onboarded, in Wellington.
  insert into public.profiles (id, first_name, last_name, birthday, level, formats, zip, area_label, home_point, onboarding_completed_at)
  values
    (a, 'Maya', 'Reyes', '1996-03-14', 'intermediate', '{casual,singles}', '33411', 'Royal Palm Beach, FL',
     extensions.st_setsrid(extensions.st_makepoint(-80.2284, 26.7084), 4326), now()),
    (b, 'Jordan', 'Tate', '1994-05-02', 'intermediate', '{casual}', '33414', 'Wellington, FL',
     extensions.st_setsrid(extensions.st_makepoint(-80.2414, 26.6618), 4326), now()),
    (c, 'Alex', 'Okafor', '1990-01-20', 'advanced', '{singles}', '33414', 'Wellington, FL',
     extensions.st_setsrid(extensions.st_makepoint(-80.2414, 26.6618), 4326), now());
  select id into v_court from public.courts where name = 'Wellington Tennis Center';
  if v_court is null then raise exception 'seed missing: Wellington Tennis Center'; end if;

  -- Maya posts a hit.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_hit := public.create_hit(v_court, now() + interval '2 days', 90, 'casual', 1, 'anyone');
  v_hit_id := (v_hit->>'id')::uuid;
  if (v_hit->>'status') <> 'open' or (v_hit->>'spots_open')::int <> 1 then raise exception 'create_hit state: %', v_hit; end if;

  -- Jordan sees it on Play (near you), asks to join.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_feed := public.get_play_feed();
  if jsonb_array_length(v_feed->'near_you') < 1 then raise exception 'feed empty for jordan: %', v_feed; end if;
  v_req := public.request_to_join(v_hit_id);
  v_req_id := (v_req->'viewer'->'request'->>'id')::uuid;
  if v_req_id is null then raise exception 'request id missing: %', v_req; end if;
  begin
    perform public.request_to_join(v_hit_id);
    raise exception 'duplicate request allowed';
  exception when others then
    if sqlerrm not in ('already_requested') then raise; end if;
  end;

  -- Maya accepts: hit confirmed, chat exists, both are members, Jordan is notified.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_hit := public.respond_to_request(v_req_id, true);
  if (v_hit->>'status') <> 'confirmed' or (v_hit->>'spots_open')::int <> 0 then raise exception 'accept state: %', v_hit; end if;
  v_chat := (v_hit->>'chat_id')::uuid;
  if not public.is_chat_member(v_chat, a) or not public.is_chat_member(v_chat, b) then raise exception 'chat members missing'; end if;
  select count(*) into v_n from public.notifications where user_id = b and kind = 'request_accepted';
  if v_n <> 1 then raise exception 'expected 1 request_accepted notification, got %', v_n; end if;

  -- Alex cannot squeeze in: the hit is full.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin
    perform public.request_to_join(v_hit_id);
    raise exception 'full hit accepted a request';
  exception when others then
    if sqlerrm <> 'hit_full' then raise; end if;
  end;

  -- Messaging in the hit chat, idempotent on client id.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_msg := public.send_message(v_chat, '11111111-1111-1111-1111-111111111111', 'Court 4 has the best shade');
  v_msg := public.send_message(v_chat, '11111111-1111-1111-1111-111111111111', 'Court 4 has the best shade');
  select count(*) into v_n from public.messages where chat_id = v_chat and type = 'text';
  if v_n <> 1 then raise exception 'duplicate message stored (%)', v_n; end if;
  v_inbox := public.get_inbox();
  if jsonb_array_length(v_inbox) < 1 then raise exception 'inbox empty'; end if;
  select count(*) into v_n from public.notifications where user_id = a and kind = 'message';
  if v_n <> 1 then raise exception 'host should get 1 message push, got %', v_n; end if;

  -- Friends: Alex adds Jordan (pending, DM created), Jordan adds back (accepted).
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_friend := public.add_friend(b);
  if (v_friend->>'relationship') <> 'requested' then raise exception 'add_friend: %', v_friend; end if;
  begin
    perform public.send_message((v_friend->>'dm_chat_id')::uuid, gen_random_uuid(), 'hi');
    raise exception 'dm allowed before add-back';
  exception when others then
    if sqlerrm <> 'not_friends' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_friend := public.add_friend(c);
  if (v_friend->>'relationship') <> 'friend' then raise exception 'add back: %', v_friend; end if;
  -- The system line reads from each side.
  v_inbox := public.get_inbox();
  if not exists (select 1 from jsonb_array_elements(v_inbox) x where x->>'id' = v_friend->>'dm_chat_id' and x->>'preview' = 'You added Alex O. back. Say hi') then
    raise exception 'adder preview: %', v_inbox;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_inbox := public.get_inbox();
  if not exists (select 1 from jsonb_array_elements(v_inbox) x where x->>'id' = v_friend->>'dm_chat_id' and x->>'preview' = 'Jordan T. added you back. Say hi') then
    raise exception 'added preview: %', v_inbox;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform public.send_message((v_friend->>'dm_chat_id')::uuid, gen_random_uuid(), 'hey!');

  -- Group chat + hit request card + atomic claim.
  v_group := public.create_group_chat('Wellington Weekend Crew', array[c]);
  v_hit := public.create_hit(v_court, now() + interval '3 days', 60, 'drills', 1, 'invite_only', (v_group->>'id')::uuid, null);
  v_invite := (select public.invite_json(i.id, b) from public.hit_invites i where i.hit_id = (v_hit->>'id')::uuid);
  if (v_invite->>'status') <> 'open' then raise exception 'invite not open: %', v_invite; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_hit := public.claim_invite((v_invite->>'id')::uuid);
  if (v_hit->>'status') <> 'confirmed' then raise exception 'claim state: %', v_hit; end if;
  begin
    perform public.claim_invite((v_invite->>'id')::uuid);
    raise exception 'second claim succeeded';
  exception when others then
    if sqlerrm not in ('invite_closed', 'spot_taken', 'already_in') then raise; end if;
  end;

  -- Alex blocks Jordan: relationship flips, and a hit Jordan posts afterwards is invisible to Alex.
  perform public.block_user(b);
  if public.relationship_to(c, b) <> 'blocked' then raise exception 'relationship after block: %', public.relationship_to(c, b); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_hit := public.create_hit(v_court, now() + interval '4 days', 60, 'singles', 1, 'anyone');
  if public.can_see_hit((v_hit->>'id')::uuid, c) then raise exception 'blocked user still sees hit'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.unblock_user(b);

  -- Scheduler runs without error; badge works.
  perform public.run_hit_scheduler();
  if public.badge_count(a) < 0 then raise exception 'badge'; end if;

  -- My Hits states for Jordan: the confirmed hit with Maya, the drills hit he hosts.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_feed := public.get_my_hits();
  if jsonb_array_length(v_feed->'upcoming') < 2 then raise exception 'my hits upcoming: %', v_feed; end if;
  if not exists (select 1 from jsonb_array_elements(v_feed->'upcoming') e where e->>'state' = 'confirmed') then
    raise exception 'expected a confirmed row: %', v_feed->'upcoming';
  end if;

  -- Jordan leaves Maya's hit: the spot reopens, the hit goes back to open, Maya is told.
  v_hit := public.leave_hit(v_hit_id);
  if (v_hit->>'status') <> 'open' or (v_hit->>'spots_open')::int <> 1 then raise exception 'leave state: %', v_hit; end if;
  select count(*) into v_n from public.notifications where user_id = a and kind = 'player_left';
  if v_n <> 1 then raise exception 'player_left notification missing'; end if;
  begin
    perform public.leave_hit(v_hit_id);
    raise exception 'left twice';
  exception when others then
    if sqlerrm <> 'not_a_player' then raise; end if;
  end;

  -- Maya cancels it: pending state cleared, nothing left to show.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_hit := public.cancel_hit(v_hit_id);
  if (v_hit->>'status') <> 'cancelled' then raise exception 'cancel state: %', v_hit; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin
    perform public.request_to_join(v_hit_id);
    raise exception 'joined a cancelled hit';
  exception when others then
    if sqlerrm not in ('hit_closed', 'hit_not_found') then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- Reminders: a confirmed hit 50 minutes out gets the one-hour reminder, exactly once.
  v_hit := public.create_hit(v_court, now() + interval '50 minutes', 60, 'singles', 1, 'anyone');
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join((v_hit->>'id')::uuid);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
  perform public.run_hit_scheduler();
  perform public.run_hit_scheduler();
  select count(*) into v_n from public.notifications where kind = 'reminder_hour' and (data->>'hit_id')::uuid = (v_hit->>'id')::uuid;
  if v_n <> 2 then raise exception 'expected 2 one-hour reminders (host + player), got %', v_n; end if;

  -- Onboarding validation and contact matching.
  perform public.update_profile(jsonb_build_object('phone_hash', 'hash-maya', 'email_hash', 'ehash-maya', 'radius_mi', 15));
  if (public.get_me()->>'radius_mi')::int <> 15 then raise exception 'update_profile radius'; end if;
  begin
    perform public.update_profile(jsonb_build_object('radius_mi', 7));
    raise exception 'invalid radius accepted';
  exception when others then
    if sqlerrm <> 'invalid_radius' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_feed := public.match_contacts(array['hash-maya', 'nothing']);
  if jsonb_array_length(v_feed) <> 1 or (v_feed->0->'player'->>'id')::uuid <> a then raise exception 'match_contacts: %', v_feed; end if;
  update public.profiles set birthday = current_date - interval '12 years' where id = b;
  begin
    perform public.complete_onboarding();
    raise exception 'underage accepted';
  exception when others then
    if sqlerrm <> 'underage' then raise; end if;
  end;
  update public.profiles set birthday = '1994-05-02' where id = b;

  -- Row-level security as the app's role: Alex sees only hits visible to him, never Maya's profile row.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.profiles;
  if v_n <> 1 then raise exception 'rls: profiles visible to others (%)', v_n; end if;
  select count(*) into v_n from public.hits where host_id = a and status = 'cancelled';
  if v_n <> 0 then raise exception 'rls: cancelled hit of a stranger is visible'; end if;
  select count(*) into v_n from public.player_cards;
  if v_n < 2 then raise exception 'rls: player_cards should list the other active players (%)', v_n; end if;
  execute 'reset role';

  -- Deletion anonymizes without touching others' threads.
  perform public.internal_delete_account(c, 'full');
  if (select first_name from public.profiles where id = c) <> 'Deleted' then raise exception 'delete did not anonymize'; end if;
  select count(*) into v_n from public.messages where chat_id = (v_group->>'id')::uuid;
  if v_n < 1 then raise exception 'group thread lost after deletion'; end if;

  raise exception 'SMOKE_OK';
end $$;
