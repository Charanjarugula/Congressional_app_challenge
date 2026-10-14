-- Only the app's entry points are callable over the API. Everything else (JSON builders, predicates,
-- internal writers) runs inside those security-definer functions as their owner and needs no grant;
-- left callable, profile_json or chat_json would hand any signed-in user another player's private row.
-- New functions start with no API access: a migration that adds an entry point grants it here too.

revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant execute on function
  public.add_chat_members(uuid, uuid[]),
  public.add_court(text, text, text, float8, float8, text, text, boolean),
  public.add_friend(uuid),
  public.block_user(uuid),
  public.cancel_hit(uuid),
  public.cancel_request(uuid),
  public.claim_invite(uuid),
  public.complete_onboarding(),
  public.create_group_chat(text, uuid[]),
  public.create_hit(uuid, timestamptz, integer, public.play_format, integer, public.hit_visibility, uuid, timestamptz),
  public.decline_invite(uuid),
  public.get_blocked_players(),
  public.get_chat_page(uuid, timestamptz, uuid, integer),
  public.get_friend_suggestions(uuid[]),
  public.get_friends(),
  public.get_hit(uuid),
  public.get_inbox(),
  public.get_me(),
  public.get_my_hits(),
  public.get_nearby_courts(integer),
  public.get_play_feed(),
  public.get_player(uuid),
  public.leave_chat(uuid),
  public.leave_hit(uuid),
  public.mark_chat_read(uuid),
  public.mark_request_seen(uuid),
  public.match_contacts(text[]),
  public.register_device(text, text, text),
  public.remove_friend(uuid),
  public.report_user(uuid, public.report_reason, text, boolean, uuid),
  public.request_to_join(uuid),
  public.respond_to_request(uuid, boolean),
  public.search_players(text),
  public.send_hit_invite(uuid, uuid, uuid, timestamptz),
  public.send_message(uuid, uuid, text),
  public.set_chat_muted(uuid, boolean),
  public.submit_attendance(uuid, uuid, boolean, boolean),
  public.unblock_user(uuid),
  public.unregister_device(text),
  public.update_profile(jsonb)
to authenticated;

-- Row-level security policies and the player_cards view evaluate these as the signed-in role.
grant execute on function
  public.can_see_hit(uuid, uuid),
  public.is_hit_host(uuid, uuid),
  public.is_chat_member(uuid, uuid),
  public.is_blocked_either(uuid, uuid),
  public.is_active_user(uuid)
to authenticated;

-- The auth server fires the new-user trigger.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function public.handle_new_user() to supabase_auth_admin;
  end if;
end $$;
