do $$
declare ana uuid; luis uuid; priya uuid; marcus uuid; nina uuid; ethan uuid; sarah uuid; noah uuid;
 c_well uuid; c_okee uuid; c_rpb uuid; v_group uuid; v_dm jsonb; r jsonb; req jsonb; h uuid; v_local timestamp; e record;
begin
 select id into ana from auth.users where email='recording.ana@courtly.app';
 select id into luis from auth.users where email='recording.luis@courtly.app';
 select id into priya from auth.users where email='recording.priya@courtly.app';
 select id into marcus from auth.users where email='recording.marcus@courtly.app';
 select id into nina from auth.users where email='recording.nina@courtly.app';
 select id into ethan from auth.users where email='recording.ethan@courtly.app';
 select id into sarah from auth.users where email='recording.sarah@courtly.app';
 select id into noah from auth.users where email='recording.noah@courtly.app';
 select id into c_well from public.courts where name='Wellington Tennis Center';
 select id into c_okee from public.courts where name='Okeeheelee Park Tennis Center';
 select id into c_rpb from public.courts where name='Royal Palm Beach Commons Park';
 select id into v_group from public.chats where name='Wellington Weekend Crew' and created_by=luis;
 v_local := date_trunc('day',now() at time zone 'America/New_York');
 -- Incoming requests on both phones, plus an outgoing request for Ana.
 perform set_config('request.jwt.claims',json_build_object('sub',priya,'role','authenticated')::text,true);
 perform public.add_friend(ana);
 perform set_config('request.jwt.claims',json_build_object('sub',sarah,'role','authenticated')::text,true);
 perform public.add_friend(ana);
 perform set_config('request.jwt.claims',json_build_object('sub',marcus,'role','authenticated')::text,true);
 perform public.add_friend(luis);
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.add_friend(nina);
 -- A second established friendship, useful for a busy inbox and group context.
 perform public.add_friend(ethan);
 perform set_config('request.jwt.claims',json_build_object('sub',ethan,'role','authenticated')::text,true);
 v_dm := public.add_friend(ana);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'Hi Ana! Great hitting with you last week. Same time on Sunday?');
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'Yes! I will post a hit once I check the court.');
 perform set_config('request.jwt.claims',json_build_object('sub',ethan,'role','authenticated')::text,true);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'Perfect. I can bring a fresh can of balls.');
 -- Main two-player conversation: both phones can continue it live.
 select jsonb_build_object('dm_chat_id',c.id) into v_dm from public.chats c
 where c.type='dm' and exists(select 1 from public.chat_members where chat_id=c.id and user_id=ana)
 and exists(select 1 from public.chat_members where chat_id=c.id and user_id=luis) limit 1;
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'Hey Ana! Are you up for some tennis this weekend?');
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'Absolutely. A relaxed warm-up and then a few singles games?');
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'Sounds good. Wellington is close to both of us.');
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.send_message((v_dm->>'dm_chat_id')::uuid,gen_random_uuid(),'I posted a hit for tomorrow evening. Send a request and I will add you.');
 -- Luis has a live pending join request that Ana can accept on camera.
 select id into h from public.hits where host_id=ana and format='casual' and status='open' order by starts_at limit 1;
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 perform public.request_to_join(h);
 -- Ana hosts doubles; Marcus has already joined and Priya is waiting.
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 r:=public.create_hit(c_well,(v_local+interval '2 days 10 hours') at time zone 'America/New_York',null,'doubles',3,'anyone'); h:=(r->>'id')::uuid;
 perform set_config('request.jwt.claims',json_build_object('sub',marcus,'role','authenticated')::text,true);
 req:=public.request_to_join(h);
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.respond_to_request((req->'viewer'->'request'->>'id')::uuid,true);
 perform set_config('request.jwt.claims',json_build_object('sub',priya,'role','authenticated')::text,true);
 perform public.request_to_join(h);
 -- A confirmed hit shared by both recording accounts, separate from the pending one.
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 r:=public.create_hit(c_okee,(v_local+interval '4 days 18 hours') at time zone 'America/New_York',null,'singles',1,'anyone'); h:=(r->>'id')::uuid;
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 req:=public.request_to_join(h);
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 perform public.respond_to_request((req->'viewer'->'request'->>'id')::uuid,true);
 -- Group chat and invitation card.
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.add_chat_members(v_group,array[marcus]);
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 perform public.send_message(v_group,gen_random_uuid(),'Anyone interested in doubles? We can meet by the entrance and find an open court.');
 perform set_config('request.jwt.claims',json_build_object('sub',marcus,'role','authenticated')::text,true);
 perform public.send_message(v_group,gen_random_uuid(),'Count me in. I have extra balls if we need them.');
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 perform public.create_hit(c_rpb,(v_local+interval '6 days 18 hours') at time zone 'America/New_York',null,'doubles',3,'invite_only',v_group,null);
 -- More nearby listings across levels, formats, courts and days.
 for e in select * from (values
  (nina,c_well,1,16,'singles'::public.play_format,1),
  (nina,c_rpb,3,18,'doubles',3),
  (ethan,c_okee,2,17,'casual',2),
  (ethan,c_well,5,9,'drills',3),
  (sarah,c_well,1,9,'casual',1),
  (sarah,c_rpb,4,16,'drills',2),
  (noah,c_okee,2,8,'singles',1),
  (noah,c_well,5,18,'doubles',3),
  (marcus,c_rpb,0,18,'casual',2),
  (priya,c_well,0,16,'singles',1)
 ) as x(person,court,days,hour,format,spots) loop
  perform set_config('request.jwt.claims',json_build_object('sub',e.person,'role','authenticated')::text,true);
  perform public.create_hit(e.court,greatest((v_local+make_interval(days=>e.days,hours=>e.hour)) at time zone 'America/New_York',now()+interval '2 hours'),null,e.format,e.spots,'anyone');
 end loop;
 -- Fictional history: a completed singles hit, with genuine membership and chat state.
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 r:=public.create_hit(c_rpb,(v_local+interval '7 days 10 hours') at time zone 'America/New_York',null,'singles',1,'anyone'); h:=(r->>'id')::uuid;
 perform set_config('request.jwt.claims',json_build_object('sub',luis,'role','authenticated')::text,true);
 req:=public.request_to_join(h);
 perform set_config('request.jwt.claims',json_build_object('sub',ana,'role','authenticated')::text,true);
 perform public.respond_to_request((req->'viewer'->'request'->>'id')::uuid,true);
 update public.hits set starts_at=(v_local-interval '2 days'+interval '18 hours') at time zone 'America/New_York' where id=h;
 update public.hits set status='played' where id=h;
 -- Space the scripted chat history naturally while keeping current unread messages.
 with ranked as(select id,row_number() over(partition by chat_id order by created_at,id) n,count(*) over(partition by chat_id) total from public.messages where sender_id in (ana,luis,priya,marcus,nina,ethan,sarah,noah))
 update public.messages m set created_at=now()-make_interval(mins=>((r.total-r.n)*12+5)::int) from ranked r where m.id=r.id;
 update public.chats c set last_message_at=(select max(created_at) from public.messages m where m.chat_id=c.id) where c.created_by in (ana,luis,priya,marcus,nina,ethan,sarah,noah);
 delete from public.rate_limits where user_id in (ana,luis,priya,marcus,nina,ethan,sarah,noah);
end $$;
