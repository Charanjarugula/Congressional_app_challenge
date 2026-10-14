-- What the App Review account sees: two friends and a short conversation, a group, a hit of its own
-- with one player in and one request waiting, a confirmed hit with a chat, a hit request card from
-- the group, and a hit played yesterday that still wants the day-after answer. Runs after world.sql;
-- without a reviewer account (the reviewer step makes it) there is nothing to do.
do $$
declare rv uuid; ana uuid; luis uuid; priya uuid; marcus uuid; c_well uuid; c_okee uuid; v_group uuid; v_dm jsonb; r jsonb; v_req jsonb;
        v_mine uuid; v_joined uuid; v_played uuid; v_local timestamp;
begin
  select id into rv from auth.users where email = 'reviewer@courtly.app';
  if rv is null then raise notice 'no reviewer account; the App Review world is skipped'; return; end if;
  select id into ana from auth.users where email = 'demo.ana@courtly.app';
  select id into luis from auth.users where email = 'demo.luis@courtly.app';
  select id into priya from auth.users where email = 'demo.priya@courtly.app';
  select id into marcus from auth.users where email = 'demo.marcus@courtly.app';
  select id into c_well from public.courts where name = 'Wellington Tennis Center';
  select id into c_okee from public.courts where name = 'Okeeheelee Park Tennis Center';
  select id into v_group from public.chats where type = 'group' and name = 'Wellington Weekend Crew' and created_by = luis;
  if ana is null or luis is null or priya is null or marcus is null or c_well is null or c_okee is null or v_group is null then
    raise exception 'the App Review world needs the demo players, their group and the seeded courts';
  end if;
  v_local := date_trunc('day', now() at time zone 'America/New_York');

  -- Friends: Ana and Luis, with a short conversation with Ana.
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  v_dm := public.add_friend(ana);
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform public.add_friend(rv);
  perform public.send_message((v_dm->>'dm_chat_id')::uuid, gen_random_uuid(), 'Hey! Saw you’re in Wellington too. Up for a hit this week?');
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  perform public.send_message((v_dm->>'dm_chat_id')::uuid, gen_random_uuid(), 'Definitely. Thursday evening works for me');
  perform set_config('request.jwt.claims', json_build_object('sub', luis, 'role', 'authenticated')::text, true);
  perform public.add_friend(rv);
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  perform public.add_friend(luis);

  -- The group: Luis adds the reviewer, Ana says hi.
  perform set_config('request.jwt.claims', json_build_object('sub', luis, 'role', 'authenticated')::text, true);
  perform public.add_chat_members(v_group, array[rv]);
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform public.send_message(v_group, gen_random_uuid(), 'Welcome to the crew!');

  -- The reviewer hosts the morning after tomorrow (clear of Ana's hit tomorrow and Priya's that evening):
  -- Luis is in, Priya is waiting for an answer, Luis has written in the chat.
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  r := public.create_hit(c_well, (v_local + interval '2 days 10 hours') at time zone 'America/New_York', 90, 'casual', 2, 'anyone');
  v_mine := (r->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', luis, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join(v_mine);
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  r := public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
  perform set_config('request.jwt.claims', json_build_object('sub', priya, 'role', 'authenticated')::text, true);
  perform public.request_to_join(v_mine);
  perform set_config('request.jwt.claims', json_build_object('sub', luis, 'role', 'authenticated')::text, true);
  perform public.send_message((r->>'chat_id')::uuid, gen_random_uuid(), 'Bringing a fresh can of balls. Court 3 if it’s free');

  -- The reviewer asks into Ana's casual hit tomorrow; Ana accepts, so it is confirmed with its own chat.
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  select id into v_joined from public.hits where host_id = ana and status = 'open' order by starts_at limit 1;
  v_req := public.request_to_join(v_joined);
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);

  -- Ana offers Saturday singles to the group as a hit request card.
  perform public.create_hit(c_well, (v_local + interval '3 days 17 hours') at time zone 'America/New_York', 60, 'singles', 1, 'invite_only', v_group, null);

  -- A hit the reviewer hosted yesterday with Ana: the scheduler marks it played, so My Hits asks "Did Ana show up?".
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  r := public.create_hit(c_okee, (v_local + interval '2 days 19 hours') at time zone 'America/New_York', 60, 'singles', 1, 'anyone');
  v_played := (r->>'id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join(v_played);
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
  update public.hits set starts_at = (v_local - interval '1 day' + interval '18 hours') at time zone 'America/New_York', created_at = now() - interval '3 days' where id = v_played;
  update public.messages set created_at = created_at - interval '3 days' where chat_id = (select chat_id from public.hits where id = v_played);
  perform public.run_hit_scheduler();
end $$;
