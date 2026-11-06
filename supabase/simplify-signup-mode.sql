-- SCRIMS RTG: cuentas independientes de la modalidad del torneo.
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Conserva cuentas, equipos, invitaciones, inscripciones y resultados existentes.

alter table public.profiles alter column mode drop not null;
alter table public.profiles alter column mode drop default;

create or replace function public.handle_new_scrims_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname, game_uid, mode, team_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nickname', 'Jugador'),
    coalesce(new.raw_user_meta_data->>'game_uid', 'PEND-' || replace(new.id::text, '-', '')),
    null,
    null
  );
  return new;
end;
$$;

create or replace function public.register_solo_tournament(target_tournament uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare t public.tournaments%rowtype; p public.profiles%rowtype; used_slots integer;
begin
  if auth.uid() is null then raise exception 'Inicia sesión para inscribirte.'; end if;
  select * into p from public.profiles where id=auth.uid();
  if not found or p.status <> 'Aprobado' then raise exception 'Tu cuenta debe estar aprobada.'; end if;
  select * into t from public.tournaments where id=target_tournament for update;
  if not found or t.status <> 'Abierto' then raise exception 'Este torneo no está abierto.'; end if;
  if not t.registration_open or (t.registration_closes_at is not null and now()>t.registration_closes_at) then raise exception 'Las inscripciones están cerradas.'; end if;
  if t.mode <> 'SOLO' then raise exception 'Este registro es solo para torneos SOLO.'; end if;
  select count(*) into used_slots from public.tournament_registrations where tournament_id=t.id and status <> 'Cancelado';
  if used_slots >= t.max_slots then raise exception 'El torneo ya alcanzó su cupo máximo.'; end if;
  insert into public.tournament_registrations(tournament_id,player_id) values(t.id,p.id);
exception when unique_violation then raise exception 'Ya estás inscrito en este torneo.';
end;
$$;

create or replace function public.create_and_register_team(target_tournament uuid, team_name text, teammate_uids text[])
returns uuid language plpgsql security definer set search_path = public
as $$
declare t public.tournaments%rowtype; captain public.profiles%rowtype; teammate public.profiles%rowtype; new_team uuid; expected integer; uid text; used_slots integer;
begin
 if auth.uid() is null then raise exception 'Inicia sesión para crear el equipo.'; end if;
 select * into captain from public.profiles where id=auth.uid();
 if not found or captain.status<>'Aprobado' then raise exception 'Tu cuenta debe estar aprobada.'; end if;
 select * into t from public.tournaments where id=target_tournament for update;
 if not found or t.status<>'Abierto' or not t.registration_open then raise exception 'Este torneo no está abierto a inscripciones.'; end if;
 if t.registration_closes_at is not null and now()>t.registration_closes_at then raise exception 'Las inscripciones están cerradas.'; end if;
 if t.mode not in ('DUO','SQUAD') then raise exception 'Este torneo no es de equipos.'; end if;
 expected:=case when t.mode='DUO' then 2 else 4 end;
 if coalesce(array_length(teammate_uids,1),0)<>expected-1 then raise exception 'Debes indicar exactamente % UID(s) de compañero(s).', expected-1; end if;
 if length(trim(coalesce(team_name,'')))<2 then raise exception 'Escribe un nombre de equipo válido.'; end if;
 select count(*) into used_slots from public.tournament_registrations where tournament_id=t.id and status<>'Cancelado';
 if used_slots>=t.max_slots then raise exception 'El torneo ya alcanzó su cupo máximo.'; end if;
 if exists(select 1 from public.scrim_team_members m join public.scrim_teams st on st.id=m.team_id where m.player_id=captain.id and st.tournament_id=t.id) then raise exception 'Ya perteneces a un equipo de este torneo.'; end if;
 insert into public.scrim_teams(name,mode,captain_id,tournament_id) values(trim(team_name),t.mode,captain.id,t.id) returning id into new_team;
 insert into public.scrim_team_members(team_id,player_id) values(new_team,captain.id);
 foreach uid in array teammate_uids loop
  select * into teammate from public.profiles where game_uid=trim(uid) and status='Aprobado';
  if not found then raise exception 'No se encontró un compañero aprobado con UID: %',uid; end if;
  if teammate.id=captain.id then raise exception 'No puedes invitarte a ti mismo.'; end if;
  if exists(select 1 from public.scrim_team_members m join public.scrim_teams st on st.id=m.team_id where m.player_id=teammate.id and st.tournament_id=t.id) then raise exception 'Un compañero ya pertenece a otro equipo en este torneo.'; end if;
  insert into public.scrim_team_invites(team_id,invitee_id) values(new_team,teammate.id);
 end loop;
 return new_team;
exception when unique_violation then raise exception 'El nombre del equipo ya existe o hay una invitación duplicada.';
end;
$$;

create or replace function public.accept_team_invite(target_invite uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare inv public.scrim_team_invites%rowtype; tm public.scrim_teams%rowtype; p public.profiles%rowtype; t public.tournaments%rowtype; expected integer; current_count integer; used_slots integer;
begin
 if auth.uid() is null then raise exception 'Inicia sesión para aceptar la invitación.'; end if;
 select * into inv from public.scrim_team_invites where id=target_invite and invitee_id=auth.uid() for update;
 if not found or inv.status<>'Pendiente' then raise exception 'La invitación no existe o ya fue respondida.'; end if;
 select * into tm from public.scrim_teams where id=inv.team_id for update;
 if not found or tm.tournament_id is null then raise exception 'No se encontró el torneo de este equipo.'; end if;
 select * into t from public.tournaments where id=tm.tournament_id for update;
 if not found or t.status<>'Abierto' or not t.registration_open or (t.registration_closes_at is not null and now()>t.registration_closes_at) then
  raise exception 'Las inscripciones de este torneo están cerradas.';
 end if;
 select * into p from public.profiles where id=auth.uid();
 if not found or p.status<>'Aprobado' then raise exception 'Tu cuenta debe estar aprobada.'; end if;
 if exists(select 1 from public.scrim_team_members m join public.scrim_teams st on st.id=m.team_id where m.player_id=p.id and st.tournament_id=tm.tournament_id) then
  raise exception 'Ya perteneces a otro equipo en este torneo.';
 end if;
 insert into public.scrim_team_members(team_id,player_id) values(tm.id,p.id);
 update public.scrim_team_invites set status='Aceptada' where id=inv.id;
 expected:=case when tm.mode='DUO' then 2 else 4 end;
 select count(*) into current_count from public.scrim_team_members where team_id=tm.id;
 if current_count=expected then
  select count(*) into used_slots from public.tournament_registrations where tournament_id=t.id and status<>'Cancelado';
  if used_slots>=t.max_slots then raise exception 'El torneo alcanzó su cupo máximo antes de completar el equipo.'; end if;
  insert into public.tournament_registrations(tournament_id,team_id) values(t.id,tm.id);
 end if;
end;
$$;

revoke all on function public.register_solo_tournament(uuid) from public;
grant execute on function public.register_solo_tournament(uuid) to authenticated;
revoke all on function public.create_and_register_team(uuid,text,text[]) from public;
grant execute on function public.create_and_register_team(uuid,text,text[]) to authenticated;
revoke all on function public.accept_team_invite(uuid) from public;
grant execute on function public.accept_team_invite(uuid) to authenticated;
