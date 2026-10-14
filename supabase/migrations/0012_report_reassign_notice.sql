-- A moderator who inherits an automatic report (the first "No" was taken back while theirs stands) was
-- still holding the notice sent when the report was filed. The notice goes when the report becomes theirs.

create or replace function public.submit_attendance(p_hit uuid, p_about uuid, p_showed_up boolean, p_add_friend boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_onboarded(); h public.hits; v_prev boolean; v_others_no boolean; v_report uuid; v_reporter uuid;
begin
  select * into h from public.hits where id = p_hit for update;
  if not found or h.status <> 'played' then raise exception 'hit_not_played'; end if;
  if not public.is_hit_member(p_hit, v_user) or not public.is_hit_member(p_hit, p_about) or p_about = v_user then
    raise exception 'not_a_player';
  end if;

  select showed_up into v_prev from public.attendance_checks where hit_id = p_hit and user_id = v_user and about_user_id = p_about;
  v_others_no := exists (select 1 from public.attendance_checks
                         where hit_id = p_hit and about_user_id = p_about and user_id <> v_user and showed_up = false);
  insert into public.attendance_checks (hit_id, user_id, about_user_id, showed_up) values (p_hit, v_user, p_about, p_showed_up)
  on conflict (hit_id, user_id, about_user_id) do update set showed_up = excluded.showed_up, created_at = now();

  if not p_showed_up and v_prev is distinct from false and not v_others_no then
    update public.profiles set no_shows = no_shows + 1, hits_played = greatest(hits_played - 1, 0) where id = p_about;
    insert into public.reports (reporter_id, reported_id, hit_id, reason, auto) values (v_user, p_about, p_hit, 'no_show', true);
  elsif p_showed_up and v_prev = false and not v_others_no then
    update public.profiles set no_shows = greatest(no_shows - 1, 0), hits_played = hits_played + 1 where id = p_about;
    delete from public.reports where hit_id = p_hit and reported_id = p_about and reason = 'no_show' and auto;
  elsif p_showed_up and v_prev = false and v_others_no then
    -- Someone else still says "No", so the absence stands; the automatic report moves to them instead
    -- of staying in the name of a player who took their answer back. A report is never news to its own
    -- reporter, so the notice the new reporter may have had as a moderator goes with the change.
    update public.reports set reporter_id = (
      select user_id from public.attendance_checks
      where hit_id = p_hit and about_user_id = p_about and user_id <> v_user and showed_up = false
      order by created_at limit 1)
    where hit_id = p_hit and reported_id = p_about and reason = 'no_show' and auto and reporter_id = v_user
    returning id, reporter_id into v_report, v_reporter;
    if v_report is not null then
      delete from public.notifications where user_id = v_reporter and kind = 'report' and collapse_id = 'report-' || v_report::text;
    end if;
  end if;
  if p_add_friend then perform public.add_friend(p_about); end if;
  return jsonb_build_object('ok', true);
end $$;
