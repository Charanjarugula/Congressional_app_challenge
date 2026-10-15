-- Search, contacts, photos and profile edits tightened before App Review.
--
-- Demo accounts stay out of name search and contact matching for real players too, so a real player
-- can't find "Ana" or "Priya" and befriend someone who isn't a person. Same rule as the feed and
-- suggestions in 0022: hidden from real players; demo and App Review accounts still see everyone.
--
-- Contact matches also say where each person stands with you (friend, requested, requested_me), like
-- search does, so the app never offers Add for someone you've already asked.

create or replace function public.search_players(p_query text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in(); v_q text := btrim(coalesce(p_query, ''));
begin
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((
    select jsonb_agg(public.player_card(p.id) || jsonb_build_object(
      'mutual_friends', to_jsonb(public.mutual_friend_names(v_user, p.id)),
      'relationship', public.relationship_to(v_user, p.id)
    ) order by p.first_name, p.last_name)
    from (
      select p.* from public.profiles p
      where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
        and not private.hidden_demo(v_user, p.id)
        -- First name, or first name and last initial: never more of the surname than other players see.
        and (p.first_name ilike v_q || '%' or (p.first_name || ' ' || left(p.last_name, 1)) ilike v_q || '%')
      order by p.first_name, p.last_name limit 20
    ) p
  ), '[]'::jsonb);
end $$;

create or replace function public.match_contacts(p_hashes text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_user uuid := public.assert_signed_in();
begin
  if cardinality(p_hashes) > 5000 then raise exception 'too_many_hashes'; end if;
  perform public.check_rate_limit('match_contacts', 30, interval '1 day');   -- Add friends re-checks on each visit
  return coalesce((
    select jsonb_agg(jsonb_build_object('hash', h.hash, 'player', public.player_card(p.id),
                                        'relationship', public.relationship_to(v_user, p.id)))
    from unnest(p_hashes) as h(hash)
    join public.profiles p on (p.phone_hash = h.hash or p.email_hash = h.hash)
    where p.id <> v_user and public.is_active_user(p.id) and not public.is_blocked_either(v_user, p.id)
      and not private.hidden_demo(v_user, p.id)
  ), '[]'::jsonb);
end $$;

-- Profile photos: the bucket is public, so photos load by URL without any read rule. Listing the
-- bucket (every player's folder) is no longer open to anyone; a player can only list their own
-- folder, which an upload that replaces a file needs.
drop policy if exists avatars_public_read on storage.objects;
create policy avatars_read_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- A profile can only point at a photo in its own folder, and a birthday changed after onboarding
-- still has to be 18 or more years ago.
create or replace function private.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.photo_path is distinct from old.photo_path and new.photo_path is not null
     and new.photo_path not like new.id::text || '/%' then
    raise exception 'invalid_photo';
  end if;
  if new.birthday is distinct from old.birthday and new.onboarding_completed_at is not null
     and new.birthday > (current_date - interval '18 years') then
    raise exception 'underage';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update of photo_path, birthday on public.profiles
  for each row execute function private.profiles_guard();
