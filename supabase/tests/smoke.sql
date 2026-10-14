-- End-to-end smoke test run against the dev project after each deploy.
-- Everything happens inside one DO block that ends by raising SMOKE_OK, which rolls the whole thing back.
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); d uuid := gen_random_uuid(); v_pat uuid := gen_random_uuid();
  v_court uuid; v_hit jsonb; v_hit_id uuid; v_req jsonb; v_req_id uuid; v_chat uuid; v_msg jsonb;
  v_feed jsonb; v_inbox jsonb; v_friend jsonb; v_invite jsonb; v_group jsonb; v_n integer; v_dm uuid; v_page jsonb;
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
  -- Same for a hit request card.
  v_hit := public.create_hit(v_court, now() + interval '6 days', 60, 'singles', 1, 'anyone');
  begin
    perform public.send_hit_invite((v_hit->>'id')::uuid, (v_friend->>'dm_chat_id')::uuid, b);
    raise exception 'hit request allowed before add-back';
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
  if not public.can_see_hit((v_hit->>'id')::uuid, c) then raise exception 'the invitee cannot see the invite-only hit'; end if;
  if public.can_see_hit((v_hit->>'id')::uuid, a) then raise exception 'an uninvited player sees the invite-only hit'; end if;
  if public.get_chat((v_group->>'id')::uuid)->>'last_message_type' <> 'hit_invite' then raise exception 'last_message_type: %', public.get_chat((v_group->>'id')::uuid); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin
    perform public.get_chat((v_group->>'id')::uuid);
    raise exception 'non-member read a chat';
  exception when others then
    if sqlerrm <> 'not_a_member' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
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

  -- A hit cancelled under a player can't be left: leaving would reopen it.
  v_hit := public.create_hit(v_court, now() + interval '5 days', 60, 'casual', 1, 'anyone');
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join((v_hit->>'id')::uuid);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
  perform public.cancel_hit((v_hit->>'id')::uuid);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin
    perform public.leave_hit((v_hit->>'id')::uuid);
    raise exception 'left a cancelled hit';
  exception when others then
    if sqlerrm <> 'hit_closed' then raise; end if;
  end;
  if (select status from public.hits where id = (v_hit->>'id')::uuid) <> 'cancelled' then raise exception 'cancelled hit reopened'; end if;
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
  perform public.update_profile(jsonb_build_object('phone_e164', '+15615550142', 'email_hash', 'spoofed', 'radius_mi', 15));
  if (public.get_me()->>'radius_mi')::int <> 15 then raise exception 'update_profile radius'; end if;
  -- Hashes are the server's: the phone hash comes from the number, the email hash from the verified sign-in email.
  if (select phone_hash from public.profiles where id = a) <> public.contact_hash('+15615550142') then raise exception 'phone_hash not derived'; end if;
  if (select email_hash from public.profiles where id = a) = 'spoofed' then raise exception 'client set email_hash'; end if;
  insert into auth.users (id, email) values (v_pat, 'Pat.Lee@Example.com');
  if (select email_hash from public.profiles where id = v_pat) <> public.contact_hash('pat.lee@example.com') then raise exception 'email_hash not set on sign-up'; end if;
  update auth.users set email = 'pat@example.org' where id = v_pat;
  if (select email_hash from public.profiles where id = v_pat) <> public.contact_hash('pat@example.org') then raise exception 'email_hash not updated'; end if;
  begin
    perform public.update_profile(jsonb_build_object('phone_e164', '(561) 555-0142'));
    raise exception 'unformatted phone accepted';
  exception when others then
    if sqlerrm <> 'invalid_phone' then raise; end if;
  end;
  -- The support address moderates from its first sign-in.
  insert into private.settings (key, value) values ('admin_email', 'mod@example.com') on conflict (key) do update set value = excluded.value;
  insert into auth.users (id, email) values (gen_random_uuid(), 'Mod@Example.com');
  if not exists (select 1 from public.admin_users a join auth.users u on u.id = a.user_id where u.email = 'Mod@Example.com') then raise exception 'admin not enrolled on sign-up'; end if;
  begin
    perform public.update_profile(jsonb_build_object('radius_mi', 7));
    raise exception 'invalid radius accepted';
  exception when others then
    if sqlerrm <> 'invalid_radius' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_feed := public.match_contacts(array[public.contact_hash('+15615550142'), 'nothing']);
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
  select count(*) into v_n from public.join_requests;
  if v_n <> 0 then raise exception 'rls: alex sees % requests that are neither his nor on his hits', v_n; end if;
  select count(*) into v_n from public.hit_invites;
  if v_n < 1 then raise exception 'rls: alex should see the invite sent to his group'; end if;
  execute 'reset role';

  -- Played hits and the day-after check. The reminder hit is moved into the past; the scheduler marks it played.
  update public.hits set starts_at = now() - interval '3 hours' where id = (v_hit->>'id')::uuid;
  perform public.run_hit_scheduler();
  if (select status from public.hits where id = (v_hit->>'id')::uuid) <> 'played' then raise exception 'scheduler did not mark the hit played'; end if;
  if (select hits_played from public.profiles where id = b) <> 1 then raise exception 'hits_played after play: %', (select hits_played from public.profiles where id = b); end if;
  -- Maya says Jordan didn't show: one no-show, one automatic report, the play no longer counts. Saying it twice changes nothing.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  if not (public.get_hit((v_hit->>'id')::uuid)->>'needs_attendance')::boolean then raise exception 'hit should need an answer'; end if;
  perform public.submit_attendance((v_hit->>'id')::uuid, b, false);
  perform public.submit_attendance((v_hit->>'id')::uuid, b, false);
  if (select no_shows from public.profiles where id = b) <> 1 then raise exception 'no_shows: %', (select no_shows from public.profiles where id = b); end if;
  if (select hits_played from public.profiles where id = b) <> 0 then raise exception 'hits_played after no-show'; end if;
  select count(*) into v_n from public.reports where reported_id = b and reason = 'no_show' and auto;
  if v_n <> 1 then raise exception 'expected 1 automatic no-show report, got %', v_n; end if;
  if (public.get_hit((v_hit->>'id')::uuid)->>'needs_attendance')::boolean then raise exception 'hit still needs an answer'; end if;
  -- Taking the "No" back restores the counters and withdraws the report (and the moderator's notice); a second "No" counts once more.
  insert into public.admin_users (user_id) values (c);
  select count(*) into v_n from public.notifications where user_id = c and kind = 'report';
  if v_n <> 0 then raise exception 'moderator told about a report filed before enrolment'; end if;
  perform public.submit_attendance((v_hit->>'id')::uuid, b, true);
  if (select no_shows from public.profiles where id = b) <> 0 or (select hits_played from public.profiles where id = b) <> 1 then raise exception 'no-show not taken back'; end if;
  select count(*) into v_n from public.reports where reported_id = b and reason = 'no_show' and auto;
  if v_n <> 0 then raise exception 'automatic report not withdrawn (%)', v_n; end if;
  perform public.submit_attendance((v_hit->>'id')::uuid, b, false);
  if (select no_shows from public.profiles where id = b) <> 1 then raise exception 'no_shows after the second no: %', (select no_shows from public.profiles where id = b); end if;
  select count(*) into v_n from public.reports where reported_id = b and reason = 'no_show' and auto;
  if v_n <> 1 then raise exception 'expected 1 automatic report after the second no, got %', v_n; end if;
  select count(*) into v_n from public.notifications where user_id = c and kind = 'report';
  if v_n <> 1 then raise exception 'moderator should hold exactly one report notice, got %', v_n; end if;
  perform public.submit_attendance((v_hit->>'id')::uuid, b, true);
  select count(*) into v_n from public.notifications where user_id = c and kind = 'report';
  if v_n <> 0 then raise exception 'report notice outlived the withdrawn report (%)', v_n; end if;
  perform public.submit_attendance((v_hit->>'id')::uuid, b, false);
  delete from public.admin_users where user_id = c;
  -- Jordan says Maya showed up and adds her as a friend in the same step; his past row no longer needs an answer.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform public.submit_attendance((v_hit->>'id')::uuid, a, true, true);
  if public.relationship_to(b, a) <> 'requested' then raise exception 'attendance add_friend: %', public.relationship_to(b, a); end if;
  v_feed := public.get_my_hits();
  if not exists (select 1 from jsonb_array_elements(v_feed->'past') e where (e->>'id')::uuid = (v_hit->>'id')::uuid and (e->>'needs_attendance')::boolean = false) then
    raise exception 'past row should be answered: %', v_feed->'past';
  end if;
  if exists (select 1 from jsonb_array_elements(v_feed->'past') e where (e->>'id')::uuid = v_hit_id) then
    raise exception 'past lists a hit jordan left: %', v_feed->'past';
  end if;
  perform public.mark_request_seen((v_req->'viewer'->'request'->>'id')::uuid);
  if (select seen_by_requester_at from public.join_requests where id = (v_req->'viewer'->'request'->>'id')::uuid) is null then raise exception 'mark_request_seen'; end if;

  -- Report with a block in one step, then undo the block. Maya moderates, so she is told.
  insert into public.admin_users (user_id) values (a);
  perform public.report_user(c, 'rude_or_unsafe', 'kept yelling at the next court', true);
  select count(*) into v_n from public.notifications where user_id = a and kind = 'report';
  if v_n <> 1 then raise exception 'expected 1 report notification for the moderator, got %', v_n; end if;
  if public.relationship_to(b, c) <> 'blocked' then raise exception 'report_user also_block'; end if;
  select count(*) into v_n from public.reports where reporter_id = b and reported_id = c and also_blocked;
  if v_n <> 1 then raise exception 'report row missing'; end if;
  perform public.unblock_user(c);

  -- Player profile, search, nearby courts.
  v_feed := public.get_player(a);
  if (v_feed->>'first_name') <> 'Maya' or (v_feed->>'relationship') <> 'requested' or (v_feed->>'hits_together')::int <> 1 then raise exception 'get_player: %', v_feed; end if;
  v_feed := public.search_players('Al');
  if not exists (select 1 from jsonb_array_elements(v_feed) e where (e->>'id')::uuid = c) then raise exception 'search_players: %', v_feed; end if;
  if jsonb_array_length(public.search_players('%%')) <> 0 then raise exception 'search_players treats %% as a wildcard'; end if;
  v_feed := public.get_nearby_courts(5);
  if jsonb_array_length(v_feed) < 1 or (v_feed->0->>'miles') is null then raise exception 'get_nearby_courts: %', v_feed; end if;

  -- Group membership: Maya adds Jordan back, Jordan adds her to the group, she mutes it and then leaves.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_friend := public.add_friend(b);
  if (v_friend->>'relationship') <> 'friend' then raise exception 'maya add back: %', v_friend; end if;
  -- Jordan's block dissolved his friendship with Alex; once they add each other again, Maya sees Alex suggested through Jordan.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.add_friend(b);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_friend := public.add_friend(c);
  if (v_friend->>'relationship') <> 'friend' then raise exception 'jordan and alex again: %', v_friend; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_feed := public.get_friend_suggestions();
  if not exists (select 1 from jsonb_array_elements(v_feed) e where (e->>'id')::uuid = c and e->>'source' = 'mutual' and e->>'reason' = 'Friends with Jordan') then
    raise exception 'mutual suggestion: %', v_feed;
  end if;
  -- A friend with every block marked free shows under "free this week" (unless the week has no block left).
  update public.profiles set availability_mask = (1 << 21) - 1, busy_mask_week = null where id = b;
  if public.remaining_week_mask() <> 0
     and not exists (select 1 from jsonb_array_elements(public.get_play_feed()->'free_this_week') e where (e->>'id')::uuid = b) then
    raise exception 'free_this_week missing jordan: %', public.get_play_feed()->'free_this_week';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_group := public.add_chat_members((v_group->>'id')::uuid, array[a]);
  if (v_group->>'member_count')::int <> 3 then raise exception 'add_chat_members: %', v_group; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.set_chat_muted((v_group->>'id')::uuid, true);
  if not (public.chat_json((v_group->>'id')::uuid, a)->>'muted')::boolean then raise exception 'mute not stored'; end if;
  perform public.leave_chat((v_group->>'id')::uuid);
  if (public.chat_json((v_group->>'id')::uuid, b)->>'member_count')::int <> 2 then raise exception 'leave_chat member count'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);

  -- Device tokens: a token registered twice keeps one row, moves with the phone, and only its owner can take it back.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.register_device('tok-1', 'sandbox', '1.0');
  perform public.register_device('tok-1', 'sandbox', '1.1');
  select count(*) into v_n from public.device_tokens where token = 'tok-1' and user_id = a and app_version = '1.1';
  if v_n <> 1 then raise exception 'register_device twice: % rows', v_n; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform public.unregister_device('tok-1');
  if not exists (select 1 from public.device_tokens where token = 'tok-1' and user_id = a) then raise exception 'unregister_device removed another player''s token'; end if;
  perform public.register_device('tok-1', 'sandbox');
  if (select user_id from public.device_tokens where token = 'tok-1') <> b then raise exception 'register_device did not move the token to its new owner'; end if;
  perform public.unregister_device('tok-1');
  if exists (select 1 from public.device_tokens where token = 'tok-1') then raise exception 'unregister_device kept the token'; end if;

  -- Courts: a court added where a seeded one stands is that court; a new one is created once and found again by its Apple place id.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_feed := public.add_court('Wellington Tennis Centre', '3100 Forest Hill Blvd', 'Wellington', 26.6536, -80.2493);
  if (v_feed->>'id')::uuid <> v_court then raise exception 'add_court did not reuse the seeded court: %', v_feed; end if;
  v_feed := public.add_court('Backyard Court', '1 Private Rd', 'Loxahatchee', 26.75, -80.30, 'apple-place-1', 'hard', true);
  if (v_feed->>'id')::uuid = v_court or v_feed->>'name' <> 'Backyard Court' or not (v_feed->>'lights')::boolean then raise exception 'add_court new court: %', v_feed; end if;
  if (public.add_court('Somewhere else', null, null, 26.9, -80.0, 'apple-place-1')->>'id')::uuid <> (v_feed->>'id')::uuid then raise exception 'add_court did not match the Apple place id'; end if;
  select count(*) into v_n from public.courts where created_by = a;
  if v_n <> 1 then raise exception 'expected one court added by maya, got %', v_n; end if;
  begin
    perform public.add_court('   ', null, null, 26.75, -80.30);
    raise exception 'add_court accepted an empty name';
  exception when others then
    if sqlerrm <> 'missing_name' then raise; end if;
  end;

  -- A joiner takes a pending request back: it leaves My Hits, the host can't take it back for them, and it can't go twice.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_hit := public.create_hit(v_court, now() + interval '3 days', 60, 'singles', 1, 'anyone');
  v_hit_id := (v_hit->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join(v_hit_id);
  v_req_id := (v_req->'viewer'->'request'->>'id')::uuid;
  if not exists (select 1 from jsonb_array_elements(public.get_my_hits()->'upcoming') e where (e->>'id')::uuid = v_hit_id and e->>'state' = 'pending') then
    raise exception 'pending request missing from my hits';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin
    perform public.cancel_request(v_req_id);
    raise exception 'host took back a joiner''s request';
  exception when others then
    if sqlerrm <> 'request_not_found' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.cancel_request(v_req_id);
  if (select status from public.join_requests where id = v_req_id) is distinct from 'cancelled' then raise exception 'cancel_request left the request pending'; end if;
  if exists (select 1 from jsonb_array_elements(public.get_my_hits()->'upcoming') e where (e->>'id')::uuid = v_hit_id) then raise exception 'cancelled request still in my hits'; end if;
  begin
    perform public.cancel_request(v_req_id);
    raise exception 'request taken back twice';
  exception when others then
    if sqlerrm <> 'request_not_found' then raise; end if;
  end;

  -- The host offers the spot to a friend in their DM; only the invitee can decline, only once, and a declined invite can't be claimed.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_dm := public.find_dm_chat(b, c);
  if v_dm is null then raise exception 'jordan and alex have no dm'; end if;
  v_invite := public.send_hit_invite(v_hit_id, v_dm, b);
  if (v_invite->>'status') <> 'open' then raise exception 'dm invite: %', v_invite; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin
    perform public.decline_invite((v_invite->>'id')::uuid);
    raise exception 'someone else declined an invite';
  exception when others then
    if sqlerrm <> 'invite_not_found' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform public.decline_invite((v_invite->>'id')::uuid);
  if (select status from public.hit_invites where id = (v_invite->>'id')::uuid) is distinct from 'cancelled' then raise exception 'decline_invite left the invite open'; end if;
  if (select spots_open from public.hits where id = v_hit_id) is distinct from 1 then raise exception 'declining changed the spot count'; end if;
  begin
    perform public.decline_invite((v_invite->>'id')::uuid);
    raise exception 'invite declined twice';
  exception when others then
    if sqlerrm <> 'invite_not_found' then raise; end if;
  end;
  begin
    perform public.claim_invite((v_invite->>'id')::uuid);
    raise exception 'claimed a declined invite';
  exception when others then
    if sqlerrm <> 'invite_closed' then raise; end if;
  end;

  -- Friend lists read from each side with the DM attached; removing a friend clears both lists and keeps the thread for an add-back.
  v_feed := public.get_friends();
  if jsonb_array_length(v_feed) <> 2 or v_feed->0->>'first_name' <> 'Alex' or v_feed->1->>'first_name' <> 'Maya' then raise exception 'jordan''s friends: %', v_feed; end if;
  if not exists (select 1 from jsonb_array_elements(v_feed) e where (e->>'id')::uuid = a and e->>'relationship' = 'friend'
                 and e->>'dm_chat_id' is not distinct from public.find_dm_chat(a, b)::text) then
    raise exception 'get_friends row for maya: %', v_feed;
  end if;
  v_dm := public.find_dm_chat(a, b);
  if v_dm is null then raise exception 'maya and jordan have no dm'; end if;
  perform public.remove_friend(a);
  if exists (select 1 from jsonb_array_elements(public.get_friends()) e where (e->>'id')::uuid = a) then raise exception 'remove_friend left maya on jordan''s list'; end if;
  if public.relationship_to(a, b) <> 'none' then raise exception 'relationship after removal: %', public.relationship_to(a, b); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  if exists (select 1 from jsonb_array_elements(public.get_friends()) e where (e->>'id')::uuid = b) then raise exception 'remove_friend left jordan on maya''s list'; end if;
  v_friend := public.add_friend(b);
  if (v_friend->>'relationship') <> 'requested' then raise exception 'add after removal: %', v_friend; end if;
  if (v_friend->>'dm_chat_id')::uuid is distinct from v_dm then raise exception 'add-back opened a second dm: %', v_friend; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  if (public.add_friend(a)->>'relationship') <> 'friend' then raise exception 'add back after removal'; end if;

  -- The blocked list is the blocker's own and empties on unblock.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  if jsonb_array_length(public.get_blocked_players()) <> 0 then raise exception 'maya has blocked no one yet'; end if;
  perform public.block_user(c);
  v_feed := public.get_blocked_players();
  if jsonb_array_length(v_feed) <> 1 or (v_feed->0->>'id')::uuid <> c or v_feed->0->>'first_name' <> 'Alex' then raise exception 'get_blocked_players: %', v_feed; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  if jsonb_array_length(public.get_blocked_players()) <> 0 then raise exception 'a block shows on the blocked player''s own list'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.unblock_user(c);
  if jsonb_array_length(public.get_blocked_players()) <> 0 then raise exception 'unblock left the list'; end if;

  -- Thread pages walk back through the cursor; reading marks the chat read for the caller alone. Timestamps are spread
  -- out by hand because everything here shares one transaction clock.
  v_dm := public.find_dm_chat(b, c);
  update public.messages set created_at = created_at - interval '10 minutes' where chat_id = v_dm;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_msg := public.send_message(v_dm, gen_random_uuid(), 'first');
  update public.messages set created_at = now() - interval '3 minutes' where id = (v_msg->>'id')::uuid;
  v_msg := public.send_message(v_dm, gen_random_uuid(), 'second');
  update public.messages set created_at = now() - interval '2 minutes' where id = (v_msg->>'id')::uuid;
  v_msg := public.send_message(v_dm, gen_random_uuid(), 'third');
  update public.messages set created_at = now() - interval '1 minute' where id = (v_msg->>'id')::uuid;
  v_page := public.get_chat_page(v_dm, null, null, 2);
  if (v_page->'chat'->>'id')::uuid <> v_dm then raise exception 'page chat: %', v_page->'chat'; end if;
  if jsonb_array_length(v_page->'messages') <> 2 or v_page->'messages'->0->>'body' <> 'second' or v_page->'messages'->1->>'body' <> 'third' then
    raise exception 'newest page: %', v_page->'messages';
  end if;
  v_page := public.get_chat_page(v_dm, (v_page->'messages'->0->>'created_at')::timestamptz, (v_page->'messages'->0->>'id')::uuid, 2);
  if jsonb_array_length(v_page->'messages') <> 2 or v_page->'messages'->1->>'body' <> 'first' or v_page->'messages'->0->>'body' = 'second' then
    raise exception 'earlier page: %', v_page->'messages';
  end if;
  v_n := (public.get_chat(v_dm)->>'unread_count')::int;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  if (public.get_chat(v_dm)->>'unread_count')::int < 3 then raise exception 'alex unread: %', public.get_chat(v_dm); end if;
  perform public.mark_chat_read(v_dm);
  if (public.get_chat(v_dm)->>'unread_count')::int <> 0 then raise exception 'mark_chat_read left messages unread'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  if (public.get_chat(v_dm)->>'unread_count')::int <> v_n then raise exception 'alex''s read mark changed jordan''s unread count'; end if;
  perform public.mark_chat_read(v_dm);
  if (public.get_chat(v_dm)->>'unread_count')::int <> 0 then raise exception 'jordan still unread after marking'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin
    perform public.get_chat_page(v_dm);
    raise exception 'non-member read a thread page';
  exception when others then
    if sqlerrm <> 'not_a_member' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);

  -- A withdrawn "No" hands its report to a player still saying it; the absence counts once throughout.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_hit := public.create_hit(v_court, now() + interval '2 days', 60, 'casual', 2, 'anyone');
  v_hit_id := (v_hit->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join(v_hit_id);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join(v_hit_id);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
  update public.hits set starts_at = now() - interval '3 hours' where id = v_hit_id;
  perform public.run_hit_scheduler();
  if (select status from public.hits where id = v_hit_id) is distinct from 'played' then raise exception 'three-player hit not marked played'; end if;
  select no_shows into v_n from public.profiles where id = b;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.submit_attendance(v_hit_id, b, false);   -- Alex files the first "No": Maya, a moderator, is told
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.submit_attendance(v_hit_id, b, false);
  if (select no_shows from public.profiles where id = b) <> v_n + 1 then raise exception 'two "No" answers counted twice'; end if;
  if (select count(*) from public.reports where hit_id = v_hit_id and reported_id = b and auto) <> 1 then raise exception 'expected one automatic report'; end if;
  if not exists (select 1 from public.notifications n join public.reports r on n.collapse_id = 'report-' || r.id::text
                 where n.user_id = a and n.kind = 'report' and r.hit_id = v_hit_id and r.auto) then raise exception 'moderator not told about the automatic report'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.submit_attendance(v_hit_id, b, true);    -- Alex takes it back: the report becomes Maya's, and her notice about it goes
  if (select reporter_id from public.reports where hit_id = v_hit_id and reported_id = b and auto) is distinct from a then raise exception 'report did not pass to the player still saying no'; end if;
  if exists (select 1 from public.notifications n join public.reports r on n.collapse_id = 'report-' || r.id::text
             where n.user_id = a and n.kind = 'report' and r.hit_id = v_hit_id and r.auto) then raise exception 'moderator still told about her own report'; end if;
  if (select no_shows from public.profiles where id = b) <> v_n + 1 then raise exception 'absence lifted while maya still says no'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.submit_attendance(v_hit_id, b, true);
  if exists (select 1 from public.reports where hit_id = v_hit_id and reported_id = b and auto) then raise exception 'report kept after both took it back'; end if;
  if (select no_shows from public.profiles where id = b) <> v_n then raise exception 'absence not lifted'; end if;

  -- Nearby courts put the one played at first, whatever its distance.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  if (public.get_nearby_courts(1)->0->>'played_count')::int < 1 then raise exception 'nearby courts: the court played at should come first: %', public.get_nearby_courts(1); end if;

  -- The inbox entry describes the newest message the viewer may see: a blocked member's last word stays out of the preview and the type.
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_msg := public.send_message((v_group->>'id')::uuid, gen_random_uuid(), 'last word');
  update public.messages set created_at = created_at - interval '10 minutes' where chat_id = (v_group->>'id')::uuid and id <> (v_msg->>'id')::uuid;   -- one transaction clock: spread them out by hand
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  if public.get_chat((v_group->>'id')::uuid)->>'preview' not like '%last word%' then raise exception 'preview before block: %', public.get_chat((v_group->>'id')::uuid); end if;
  perform public.block_user(c);
  v_feed := public.get_chat((v_group->>'id')::uuid);
  if v_feed->>'preview' like '%last word%' or v_feed->>'last_message_type' is null then raise exception 'blocked member''s last word in the inbox entry: %', v_feed; end if;
  perform public.unblock_user(c);
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform public.add_friend(b);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  if (public.add_friend(c)->>'relationship') <> 'friend' then raise exception 'jordan and alex not friends again'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);

  -- Every writer has a daily limit; the twenty-first group of the day is refused.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  insert into public.rate_limits (user_id, action, window_start, count) values (b, 'create_group_chat', date_trunc('day', now()), 20)
  on conflict (user_id, action, window_start) do update set count = 20;
  begin
    perform public.create_group_chat('One too many', array[c]);
    raise exception 'the daily group limit did not hold';
  exception when others then
    if sqlerrm <> 'rate_limited' then raise; end if;
  end;
  delete from public.rate_limits where user_id = b and action = 'create_group_chat';

  -- The daily purge drops reports older than 90 days (their moderator notices go too) and stale rate-limit rows;
  -- the push sweep sends what the webhook didn't deliver to the stored function URL.
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  insert into public.reports (reporter_id, reported_id, reason, details) values (b, c, 'rude_or_unsafe', 'long ago');
  update public.reports set created_at = now() - interval '100 days' where reporter_id = b and details = 'long ago';
  if not exists (select 1 from public.notifications n join public.reports r on n.collapse_id = 'report-' || r.id::text
                 where r.details = 'long ago' and n.user_id = a) then raise exception 'moderator not told about the old report'; end if;
  perform public.check_rate_limit('purge_probe', 5, interval '1 minute');
  update public.rate_limits set window_start = now() - interval '3 days' where user_id = b and action = 'purge_probe';
  insert into public.notifications (user_id, kind, title, body, created_at) values (a, 'message', 'Old', 'forty days ago', now() - interval '40 days');
  perform public.purge_old_reports();
  if exists (select 1 from public.reports where details = 'long ago') then raise exception 'purge kept a 100-day-old report'; end if;
  if exists (select 1 from public.notifications where body = 'forty days ago') then raise exception 'purge kept a 40-day-old notification'; end if;
  if exists (select 1 from public.notifications n where n.kind = 'report'
             and not exists (select 1 from public.reports r where 'report-' || r.id::text = n.collapse_id)) then raise exception 'a report notice outlived its report'; end if;
  if exists (select 1 from public.rate_limits where user_id = b and action = 'purge_probe') then raise exception 'purge kept a stale rate-limit row'; end if;
  delete from private.settings where key in ('functions_url', 'webhook_secret');
  insert into private.settings (key, value) values ('functions_url', 'https://functions.test'), ('webhook_secret', 'test-secret');
  update public.notifications set created_at = now() - interval '3 minutes' where user_id = a and pushed_at is null;
  perform public.resend_unpushed();

  -- Suspension closes the player's future hits the way a host cancel does, cancels what they had pending,
  -- refuses them a spot, shows them nothing, and lifting it leaves the hits closed.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_hit := public.create_hit(v_court, now() + interval '6 days', 60, 'casual', 1, 'anyone');
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join((v_hit->>'id')::uuid);
  perform private.suspend_user(c, true);
  if exists (select 1 from public.hits where host_id = c and starts_at > now() and status <> 'cancelled') then raise exception 'suspension left a hit open'; end if;
  if (select status from public.join_requests where id = (v_req->'viewer'->'request'->>'id')::uuid) is distinct from 'cancelled' then raise exception 'suspension left a request pending'; end if;
  begin
    perform public.add_player((v_hit->>'id')::uuid, c, 'ask');
    raise exception 'a suspended player got a spot';
  exception when others then
    if sqlerrm <> 'player_unavailable' then raise; end if;
  end;
  execute 'set local role authenticated';
  select count(*) into v_n from public.hits;
  if v_n <> 0 then raise exception 'rls: suspended player still sees % hits', v_n; end if;
  select count(*) into v_n from public.messages;
  if v_n <> 0 then raise exception 'rls: suspended player still reads % messages', v_n; end if;
  execute 'reset role';
  perform private.suspend_user(c, false);
  if (select suspended_at from public.profiles where id = c) is not null then raise exception 'suspension not lifted'; end if;

  -- Signing in with Apple again replaces the stored refresh token instead of colliding on the vault name.
  perform public.internal_store_apple_token(c, 'apple-refresh-1');
  perform public.internal_store_apple_token(c, 'apple-refresh-2');
  if public.internal_apple_refresh_token(c) <> 'apple-refresh-2' then raise exception 'apple token not replaced'; end if;
  select count(*) into v_n from vault.secrets where name = 'apple-refresh-' || c::text;
  if v_n <> 1 then raise exception 'expected one vault secret, got %', v_n; end if;

  -- Only the app's entry points are callable over the API; policies keep their predicates.
  if has_function_privilege('authenticated', 'public.profile_json(uuid)', 'execute') then raise exception 'profile_json is callable by the app role'; end if;
  if has_function_privilege('authenticated', 'public.chat_json(uuid, uuid)', 'execute') then raise exception 'chat_json is callable by the app role'; end if;
  if has_function_privilege('authenticated', 'public.find_dm_chat(uuid, uuid)', 'execute') then raise exception 'find_dm_chat is callable by the app role'; end if;
  if has_function_privilege('anon', 'public.get_me()', 'execute') then raise exception 'get_me is callable by anon'; end if;
  if not has_function_privilege('authenticated', 'public.get_me()', 'execute') then raise exception 'get_me is not callable by the app role'; end if;
  if not has_function_privilege('authenticated', 'public.viewer_can_see_hit(uuid)', 'execute') then raise exception 'viewer_can_see_hit must stay callable for policies'; end if;
  if has_function_privilege('authenticated', 'public.is_blocked_either(uuid, uuid)', 'execute') then raise exception 'is_blocked_either answers about any two players'; end if;
  if has_function_privilege('authenticated', 'public.is_chat_member(uuid, uuid)', 'execute') then raise exception 'is_chat_member answers about any player'; end if;
  if has_table_privilege('authenticated', 'public.chats', 'select') then raise exception 'chats rows are readable raw'; end if;
  if not has_table_privilege('authenticated', 'public.messages', 'select') then raise exception 'messages must stay readable for realtime'; end if;
  if not has_function_privilege('service_role', 'public.internal_delete_account(uuid, text)', 'execute') then raise exception 'service role lost internal_delete_account'; end if;

  -- Underage deletion removes a half-onboarded account outright, with the friend request and DM it opened.
  insert into public.profiles (id, first_name, last_name) values (d, 'Sam', 'Lee');
  perform set_config('request.jwt.claims', json_build_object('sub', d, 'role', 'authenticated')::text, true);
  v_friend := public.add_friend(a);
  perform public.internal_delete_account(d, 'underage');
  if exists (select 1 from public.profiles where id = d) then raise exception 'underage profile kept'; end if;
  if exists (select 1 from public.friendships where d in (user_a, user_b)) then raise exception 'underage friendship kept'; end if;
  if exists (select 1 from public.chats where id = (v_friend->>'dm_chat_id')::uuid) then raise exception 'underage dm kept'; end if;

  -- Deletion anonymizes without touching others' threads, drops the Apple secret and keeps the day-after
  -- answers the player gave. An onboarded account asking for the underage path gets this one.
  perform public.internal_delete_account(c, 'underage');
  if (select first_name from public.profiles where id = c) is distinct from 'Deleted' then raise exception 'delete did not anonymize'; end if;
  if not exists (select 1 from public.attendance_checks where user_id = c) then raise exception 'deletion removed the answers the player gave'; end if;
  if exists (select 1 from vault.secrets where name = 'apple-refresh-' || c::text) then raise exception 'vault secret kept after deletion'; end if;
  select count(*) into v_n from public.messages where chat_id = (v_group->>'id')::uuid;
  if v_n < 1 then raise exception 'group thread lost after deletion'; end if;

  raise exception 'SMOKE_OK';
end $$;
