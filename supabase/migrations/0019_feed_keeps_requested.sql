-- A hit the player has asked to join stays in their feed, marked as asked, so the ask can be taken
-- back from the same place instead of the row vanishing.

create or replace function public.feed_candidate(p_hit uuid, p_viewer uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hits h join public.profiles hp on hp.id = h.host_id
    where h.id = p_hit and h.status in ('open', 'confirmed') and h.spots_open > 0 and h.starts_at > now()
      and h.host_id <> p_viewer and h.visibility <> 'invite_only'
      and hp.suspended_at is null and hp.deleted_at is null and hp.onboarding_completed_at is not null
      and not public.is_blocked_either(p_viewer, h.host_id)
      and not exists (select 1 from public.hit_players p where p.hit_id = h.id and p.user_id = p_viewer and p.left_at is null)
      and ((h.visibility = 'anyone' and hp.hit_visibility = 'anyone') or (h.visibility in ('anyone', 'friends') and public.is_friend(p_viewer, h.host_id)))
  );
$$;
