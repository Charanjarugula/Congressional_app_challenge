-- Full-name input should find the public first-name/initial card.
CREATE OR REPLACE FUNCTION public.search_players(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid := private.assert_adult(); v_q text := regexp_replace(btrim(coalesce(p_query, '')), '[[:space:]]+', ' ', 'g'); v_initial text;
begin
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  -- Accept a typed surname by matching only its public initial; do not query or disclose the private surname.
  v_initial := regexp_replace(v_q, '( +)([^ ])[^ ]*$', '\1\2');
  v_initial := replace(replace(replace(v_initial, '\', '\\'), '%', '\%'), '_', '\_');
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
        and (p.first_name ilike v_q || '%' or (p.first_name || ' ' || left(p.last_name, 1)) ilike v_initial || '%')
      order by p.first_name, p.last_name limit 20
    ) p
  ), '[]'::jsonb);
end $function$;
