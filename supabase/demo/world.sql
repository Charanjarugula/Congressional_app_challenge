-- What the demo players have going on: Ana and Luis are friends with a group chat, Marcus knows Ana,
-- and each of the four hosts a hit or two over the coming week. Dates are relative to today in Palm
-- Beach County, so the world always lies a few days ahead. Runs after reset.sql and players.sql.
do $$
declare ana uuid; luis uuid; priya uuid; marcus uuid; c_well uuid; c_okee uuid; c_rpb uuid; c_boca uuid; c_pbg uuid; c_delray uuid;
        v_chat jsonb; v_local timestamp;
begin
  select id into ana from auth.users where email = 'demo.ana@courtly.app';
  select id into luis from auth.users where email = 'demo.luis@courtly.app';
  select id into priya from auth.users where email = 'demo.priya@courtly.app';
  select id into marcus from auth.users where email = 'demo.marcus@courtly.app';
  select id into c_well from public.courts where name = 'Wellington Tennis Center';
  select id into c_okee from public.courts where name = 'Okeeheelee Park Tennis Center';
  select id into c_rpb from public.courts where name = 'Royal Palm Beach Commons Park';
  select id into c_boca from public.courts where name = 'Boca Raton Tennis Center';
  select id into c_pbg from public.courts where name = 'Palm Beach Gardens Tennis Center';
  select id into c_delray from public.courts where name = 'Delray Beach Tennis Center';
  if ana is null or luis is null or priya is null or marcus is null
     or c_well is null or c_okee is null or c_rpb is null or c_boca is null or c_pbg is null or c_delray is null then
    raise exception 'the demo world needs the four demo players and the seeded courts';
  end if;
  v_local := date_trunc('day', now() at time zone 'America/New_York');

  -- Ana and Luis: friends, a group Luis started, a drills hit of his.
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform public.add_friend(luis);
  perform set_config('request.jwt.claims', json_build_object('sub', luis, 'role', 'authenticated')::text, true);
  perform public.add_friend(ana);
  v_chat := public.create_group_chat('Wellington Weekend Crew', array[ana]);
  perform public.send_message((v_chat->>'id')::uuid, gen_random_uuid(), 'Courts 5–8 have lights now, evening hits are back on');
  perform public.create_hit(c_okee, (v_local + interval '3 days 9 hours') at time zone 'America/New_York', 60, 'drills', 2, 'anyone');

  -- Ana: a casual hit tomorrow evening and singles at the weekend.
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform public.create_hit(c_well, (v_local + interval '1 day 18 hours 30 minutes') at time zone 'America/New_York', 90, 'casual', 1, 'anyone');
  perform public.create_hit(c_rpb, (v_local + interval '5 days 19 hours') at time zone 'America/New_York', 90, 'singles', 1, 'anyone');
  perform public.send_message((v_chat->>'id')::uuid, gen_random_uuid(), 'I posted a casual hit for tomorrow evening if anyone is free');

  -- Priya and Marcus further south and north, so Near you reaches past Wellington.
  perform set_config('request.jwt.claims', json_build_object('sub', priya, 'role', 'authenticated')::text, true);
  perform public.create_hit(c_boca, (v_local + interval '2 days 19 hours') at time zone 'America/New_York', 90, 'singles', 1, 'anyone');
  perform public.create_hit(c_delray, (v_local + interval '6 days 8 hours') at time zone 'America/New_York', 60, 'casual', 1, 'anyone');
  perform set_config('request.jwt.claims', json_build_object('sub', marcus, 'role', 'authenticated')::text, true);
  perform public.create_hit(c_pbg, (v_local + interval '4 days 10 hours') at time zone 'America/New_York', 120, 'doubles', 3, 'anyone');

  -- Marcus and Ana are friends, so Marcus turns up as "Friends with Ana" under suggestions.
  perform public.add_friend(ana);
  perform set_config('request.jwt.claims', json_build_object('sub', ana, 'role', 'authenticated')::text, true);
  perform public.add_friend(marcus);
end $$;
