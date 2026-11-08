-- SCRIMS RTG · Completar perfil de jugador después del primer acceso con Discord
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor > New query.
-- No modifica perfiles existentes que ya tengan un UID real.

create or replace function public.complete_discord_player_profile(
  player_nickname text,
  player_uid text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_nickname text := trim(coalesce(player_nickname, ''));
  clean_uid text := trim(coalesce(player_uid, ''));
begin
  if current_user_id is null then
    raise exception 'Debes iniciar sesión para completar tu perfil.';
  end if;

  if char_length(clean_nickname) < 2 or char_length(clean_nickname) > 24 then
    raise exception 'El nickname debe tener entre 2 y 24 caracteres.';
  end if;

  if char_length(clean_uid) < 3 or char_length(clean_uid) > 40 then
    raise exception 'El UID debe tener entre 3 y 40 caracteres.';
  end if;

  update public.profiles
  set nickname = clean_nickname,
      game_uid = clean_uid
  where id = current_user_id
    and game_uid like 'PEND-%';

  if not found then
    raise exception 'No hay un perfil pendiente de completar para esta cuenta.';
  end if;
end;
$$;

revoke all on function public.complete_discord_player_profile(text, text) from public;
grant execute on function public.complete_discord_player_profile(text, text) to authenticated;
