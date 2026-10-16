-- Keep invitation badges aligned with membership and make repeat acceptance idempotent.
create or replace function public.badge_count(p_user uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from public.join_requests r join public.hits h on h.id = r.hit_id
     where h.host_id = p_user and r.status = 'pending' and h.status in ('open', 'confirmed') and h.starts_at > now())
    + (select count(*) from public.hit_invites i join public.hits h on h.id = i.hit_id
       where i.target_user_id = p_user and i.status = 'open' and i.expires_at > now() and h.status in ('open', 'confirmed') and h.starts_at > now()
         and h.spots_open > 0 and not public.is_hit_member(h.id, p_user))
    + (select count(*) from public.chat_members cm
       where cm.user_id = p_user and cm.left_at is null and exists (
         select 1 from public.messages m where m.chat_id = cm.chat_id and m.sender_id is distinct from p_user
           and m.created_at > coalesce(cm.last_read_at, '-infinity'::timestamptz)
           and (m.sender_id is null or not public.is_blocked_either(p_user, m.sender_id))))
    + public.friend_request_count(p_user)
  )::integer;
$$;

create or replace function public.claim_invite(p_invite uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); i public.hit_invites; h public.hits;
begin
  select hh.* into h from public.hits hh where hh.id = (select hit_id from public.hit_invites where id = p_invite) for update;
  if not found then raise exception 'invite_not_found'; end if;
  select * into i from public.hit_invites where id = p_invite for update;
  if i.target_user_id is not null and i.target_user_id <> v_user then raise exception 'not_for_you'; end if;
  if i.target_user_id is null and not public.is_chat_member(i.chat_id, v_user) then raise exception 'not_a_member'; end if;
  -- A stale card or a repeated tap opens the existing membership without adding a player twice.
  if public.is_hit_member(h.id, v_user) then
    return public.hit_json(h.id, v_user);
  end if;
  if i.status <> 'open' or i.expires_at < now() then raise exception 'invite_closed'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'spot_taken'; end if;
  if h.host_id = v_user or public.is_hit_member(h.id, v_user) then raise exception 'already_in'; end if;
  if public.is_blocked_either(v_user, h.host_id) then raise exception 'player_unavailable'; end if;

  perform public.add_player(h.id, v_user, 'invite');
  update public.hit_invites set claimed = claimed + 1,
    status = case when claimed + 1 >= spots then 'filled' else status end
  where id = p_invite;

  select * into h from public.hits where id = h.id;
  perform public.system_message(h.chat_id, public.display_name(v_user) || ' is in',
    jsonb_build_object('event', 'player_joined', 'actor', v_user));
  perform public.notify(h.host_id, 'player_joined', 'Courtly',
    public.display_name(v_user) || ' is in for ' || public.hit_push_label(h.id),
    'courtly://hit/' || h.id, 'hit-' || h.id, jsonb_build_object('hit_id', h.id));
  return public.hit_json(h.id, v_user);
end $$;

CREATE OR REPLACE FUNCTION public.add_player(p_hit uuid, p_user uuid, p_source player_source)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.hits; v_chat uuid; r record;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found then raise exception 'hit_not_found'; end if;
  if h.status not in ('open', 'confirmed') or h.starts_at <= now() then raise exception 'hit_closed'; end if;
  if h.spots_open <= 0 then raise exception 'hit_full'; end if;
  if h.host_id = p_user then raise exception 'already_in'; end if;
  if exists (select 1 from public.hit_players where hit_id = p_hit and user_id = p_user and left_at is null) then
    raise exception 'already_in';
  end if;
  if not public.is_active_user(p_user) then raise exception 'player_unavailable'; end if;
  if exists (select 1 from public.hit_players x where x.hit_id = p_hit and x.left_at is null
             and public.is_blocked_either(p_user, x.user_id)) then raise exception 'player_unavailable'; end if;
  if public.has_overlapping_hit(p_user, h.starts_at, h.duration_min, p_hit) then raise exception 'overlaps_hit'; end if;

  insert into public.hit_players (hit_id, user_id, role, source) values (p_hit, p_user, 'player', p_source)
  on conflict (hit_id, user_id) do update set left_at = null, joined_at = now(), source = excluded.source;

  -- A direct invite is for one recipient, regardless of the hit's remaining capacity.
  update public.hit_invites set status = 'filled'
    where hit_id = p_hit and target_user_id = p_user and status = 'open';

  update public.hits set spots_open = spots_open - 1, status = 'confirmed' where id = p_hit returning * into h;

  v_chat := public.ensure_hit_chat(p_hit);
  insert into public.chat_members (chat_id, user_id) values (v_chat, p_user)
  on conflict (chat_id, user_id) do update set left_at = null;

  if h.spots_open = 0 then
    update public.hit_invites set status = 'filled' where hit_id = p_hit and status = 'open';
    for r in update public.join_requests set status = 'expired', responded_at = now()
             where hit_id = p_hit and status = 'pending' returning user_id loop
      perform public.notify(r.user_id, 'request_declined', 'Courtly',
        public.hit_push_label(p_hit) || ' filled up before the host could answer you.',
        'courtly://play', 'hit-' || p_hit, jsonb_build_object('hit_id', p_hit));
    end loop;
  end if;
end $function$;

-- Repair existing direct invitations whose recipient has already joined.
update public.hit_invites i set status = 'filled'
where i.status = 'open' and i.target_user_id is not null
  and public.is_hit_member(i.hit_id, i.target_user_id);
