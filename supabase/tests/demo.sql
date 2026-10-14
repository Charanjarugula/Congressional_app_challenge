-- Looks at the demo world from the App Review account's side, through the same calls the app makes,
-- and raises when a piece the reviewer is meant to see is missing. Reads only.
do $$
declare rv uuid; f jsonb; m jsonb; i jsonb; v_friends integer;
begin
  select id into rv from auth.users where email = 'reviewer@courtly.app';
  if rv is null then raise exception 'DEMO_CHECK no reviewer account'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', rv, 'role', 'authenticated')::text, true);
  f := public.get_play_feed(); m := public.get_my_hits(); i := public.get_inbox();
  select count(*) into v_friends from public.friendships x where rv in (x.user_a, x.user_b);
  if v_friends <> 2 then raise exception 'DEMO_CHECK friends: % (wanted 2)', v_friends; end if;
  -- Priya's request to the reviewer's hit waits for an answer.
  if not exists (select 1 from jsonb_array_elements(f->'needs_reply') e where e->>'kind' = 'join_request') then
    raise exception 'DEMO_CHECK nothing needs a reply: %', f->'needs_reply';
  end if;
  -- Luis's drills, Ana's weekend singles and the group's hit request card reach the feed.
  if jsonb_array_length(f->'from_friends') < 2 then raise exception 'DEMO_CHECK from_friends: %', f->'from_friends'; end if;
  if jsonb_array_length(f->'near_you') + jsonb_array_length(f->'from_friends') < 3 then raise exception 'DEMO_CHECK feed too empty: %', f; end if;
  -- Ana's hit tomorrow and the reviewer's own the morning after, both confirmed.
  if (select count(*) from jsonb_array_elements(m->'upcoming') e where e->>'status' = 'confirmed') < 2 then
    raise exception 'DEMO_CHECK upcoming: %', m->'upcoming';
  end if;
  -- Yesterday's hit with Ana is played and still wants the day-after answer.
  if not exists (select 1 from jsonb_array_elements(m->'past') e where e->>'state' = 'played' and (e->>'needs_attendance')::boolean) then
    raise exception 'DEMO_CHECK past: %', m->'past';
  end if;
  -- The reviewer's own line in the group is there (its removal is checked against it later).
  if not exists (select 1 from public.messages m where m.sender_id = rv and m.body like 'Thanks! Saturday mornings%') then
    raise exception 'DEMO_CHECK the reviewer''s group message is missing';
  end if;
  -- The conversation with Ana, the group, and the two hit chats.
  if jsonb_array_length(i) < 4 then raise exception 'DEMO_CHECK inbox has % chats (wanted 4)', jsonb_array_length(i); end if;
end $$;
