-- SCRIMS RTG · Inscripciones, equipos y cupos
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor > New query.
-- No elimina ni modifica los resultados existentes.

alter table public.tournaments
  add column if not exists max_slots integer not null default 100 check (max_slots between 1 and 1000),
  add column if not exists registration_open boolean not null default true,
  add column if not exists registration_closes_at timestamptz;

create table if not exists public.scrim_teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mode text not null check (mode in ('DUO','SQUAD')),
  captain_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (name, mode)
);

create table if not exists public.scrim_team_members (
  team_id uuid not null references public.scrim_teams(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (team_id, player_id),
  unique (player_id)
);

create table if not exists public.tournament_registrations (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  player_id uuid references public.profiles(id) on delete cascade,
  team_id uuid references public.scrim_teams(id) on delete cascade,
  status text not null default 'Inscrito' check (status in ('Inscrito','Cancelado','Confirmado')),
  created_at timestamptz not null default now(),
  constraint registration_exactly_one_subject check (
    (player_id is not null and team_id is null) or
    (player_id is null and team_id is not null)
  )
);

create unique index if not exists one_player_registration_per_tournament
on public.tournament_registrations(tournament_id, player_id) where player_id is not null;
create unique index if not exists one_team_registration_per_tournament
on public.tournament_registrations(tournament_id, team_id) where team_id is not null;

alter table public.match_results
  add column if not exists team_id uuid references public.scrim_teams(id) on delete set null;

alter table public.scrim_teams enable row level security;
alter table public.scrim_team_members enable row level security;
alter table public.tournament_registrations enable row level security;

grant select on public.scrim_teams, public.scrim_team_members, public.tournament_registrations to anon, authenticated;
grant insert, update, delete on public.scrim_teams, public.scrim_team_members, public.tournament_registrations to authenticated;

drop policy if exists "Public can view teams" on public.scrim_teams;
create policy "Public can view teams" on public.scrim_teams for select to anon, authenticated using (true);
drop policy if exists "Public can view team members" on public.scrim_team_members;
create policy "Public can view team members" on public.scrim_team_members for select to anon, authenticated using (true);
drop policy if exists "Players see own tournament registrations and admins see all" on public.tournament_registrations;
create policy "Players see own tournament registrations and admins see all"
on public.tournament_registrations for select to authenticated
using (
  public.is_scrims_admin()
  or player_id = auth.uid()
  or exists (select 1 from public.scrim_team_members m where m.team_id = tournament_registrations.team_id and m.player_id = auth.uid())
);
drop policy if exists "Admins manage tournament registrations" on public.tournament_registrations;
create policy "Admins manage tournament registrations" on public.tournament_registrations for all to authenticated
using (public.is_scrims_admin()) with check (public.is_scrims_admin());

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
  if t.mode <> 'SOLO' or p.mode <> 'SOLO' then raise exception 'Este registro es solo para torneos SOLO.'; end if;
  select count(*) into used_slots from public.tournament_registrations where tournament_id=t.id and status <> 'Cancelado';
  if used_slots >= t.max_slots then raise exception 'El torneo ya alcanzó su cupo máximo.'; end if;
  insert into public.tournament_registrations(tournament_id,player_id) values(t.id,p.id);
exception when unique_violation then raise exception 'Ya estás inscrito en este torneo.';
end;
$$;

create or replace function public.create_and_register_team(target_tournament uuid, team_name text, teammate_uids text[])
returns uuid language plpgsql security definer set search_path = public
as $$
declare t public.tournaments%rowtype; captain public.profiles%rowtype; teammate public.profiles%rowtype; new_team uuid; expected integer; uid text; seen integer := 0; used_slots integer;
begin
  if auth.uid() is null then raise exception 'Inicia sesión para crear el equipo.'; end if;
  select * into captain from public.profiles where id=auth.uid();
  if not found or captain.status <> 'Aprobado' then raise exception 'Tu cuenta debe estar aprobada.'; end if;
  select * into t from public.tournaments where id=target_tournament for update;
  if not found or t.status <> 'Abierto' then raise exception 'Este torneo no está abierto.'; end if;
  if not t.registration_open or (t.registration_closes_at is not null and now()>t.registration_closes_at) then raise exception 'Las inscripciones están cerradas.'; end if;
  if t.mode not in ('DUO','SQUAD') or captain.mode <> t.mode then raise exception 'La modalidad de tu cuenta no coincide con el torneo.'; end if;
  expected := case when t.mode='DUO' then 2 else 4 end;
  if coalesce(array_length(teammate_uids,1),0) <> expected-1 then raise exception 'Debes indicar exactamente '||(expected-1)||' UID(s) de compañero(s).'; end if;
  if length(trim(coalesce(team_name,''))) < 2 then raise exception 'Escribe un nombre de equipo válido.'; end if;
  select count(*) into used_slots from public.tournament_registrations where tournament_id=t.id and status <> 'Cancelado';
  if used_slots >= t.max_slots then raise exception 'El torneo ya alcanzó su cupo máximo.'; end if;
  if exists (select 1 from public.scrim_team_members where player_id=captain.id) then raise exception 'Ya perteneces a un equipo. Contacta al administrador si necesitas cambiarlo.'; end if;
  insert into public.scrim_teams(name,mode,captain_id) values(trim(team_name),t.mode,captain.id) returning id into new_team;
  insert into public.scrim_team_members(team_id,player_id) values(new_team,captain.id);
  foreach uid in array teammate_uids loop
    select * into teammate from public.profiles where game_uid=trim(uid) and mode=t.mode and status='Aprobado';
    if not found then raise exception 'No se encontró un compañero aprobado con UID: %',uid; end if;
    if teammate.id=captain.id then raise exception 'No puedes agregarte como tu propio compañero.'; end if;
    if exists(select 1 from public.scrim_team_members where player_id=teammate.id) then raise exception 'Un compañero ya pertenece a otro equipo.'; end if;
    insert into public.scrim_team_members(team_id,player_id) values(new_team,teammate.id);
    seen := seen+1;
  end loop;
  insert into public.tournament_registrations(tournament_id,team_id) values(t.id,new_team);
  return new_team;
exception when unique_violation then raise exception 'El nombre del equipo ya existe o un jugador ya está inscrito en otro equipo.';
end;
$$;

create or replace function public.cancel_my_tournament_registration(target_registration uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión.'; end if;
  update public.tournament_registrations r set status='Cancelado'
  where r.id=target_registration and (
    r.player_id=auth.uid() or exists(select 1 from public.scrim_team_members m where m.team_id=r.team_id and m.player_id=auth.uid())
  );
  if not found then raise exception 'No se encontró una inscripción tuya.'; end if;
end;
$$;

revoke all on function public.register_solo_tournament(uuid) from public;
revoke all on function public.create_and_register_team(uuid,text,text[]) from public;
revoke all on function public.cancel_my_tournament_registration(uuid) from public;
grant execute on function public.register_solo_tournament(uuid) to authenticated;
grant execute on function public.create_and_register_team(uuid,text,text[]) to authenticated;
grant execute on function public.cancel_my_tournament_registration(uuid) to authenticated;

-- Solo administradores pueden cambiar cupos, fechas de cierre y publicar/finalizar torneos.

create or replace function public.get_tournament_registration_counts()
returns table(tournament_id uuid, registered bigint)
language sql stable security definer set search_path = public
as $$
  select t.id, count(r.id)
  from public.tournaments t
  left join public.tournament_registrations r
    on r.tournament_id=t.id and r.status <> 'Cancelado'
  where t.status <> 'Borrador'
  group by t.id;
$$;
revoke all on function public.get_tournament_registration_counts() from public;
grant execute on function public.get_tournament_registration_counts() to anon, authenticated;

create table if not exists public.team_results (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  team_id uuid not null references public.scrim_teams(id) on delete cascade,
  placement integer not null default 0 check (placement >= 0),
  kills integer not null default 0 check (kills >= 0),
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default now(),
  unique (tournament_id, team_id)
);
alter table public.team_results enable row level security;
grant select on public.team_results to anon, authenticated;
grant insert, update, delete on public.team_results to authenticated;
drop policy if exists "Public can view team results" on public.team_results;
create policy "Public can view team results" on public.team_results for select to anon, authenticated using (true);
drop policy if exists "Admins manage team results" on public.team_results;
create policy "Admins manage team results" on public.team_results for all to authenticated using (public.is_scrims_admin()) with check (public.is_scrims_admin());


-- Invitaciones con aceptación explícita de cada compañero.
alter table public.scrim_teams add column if not exists tournament_id uuid references public.tournaments(id) on delete cascade;
alter table public.scrim_team_members drop constraint if exists scrim_team_members_player_id_key;

create table if not exists public.scrim_team_invites (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.scrim_teams(id) on delete cascade,
 invitee_id uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'Pendiente' check (status in ('Pendiente','Aceptada','Rechazada')),
 created_at timestamptz not null default now(),
 unique(team_id,invitee_id)
);
alter table public.scrim_team_invites enable row level security;
grant select on public.scrim_team_invites to authenticated;
drop policy if exists "Players see their team invitations" on public.scrim_team_invites;
create policy "Players see their team invitations" on public.scrim_team_invites
for select to authenticated using (
 invitee_id=auth.uid() or exists(select 1 from public.scrim_teams t where t.id=team_id and t.captain_id=auth.uid()) or public.is_scrims_admin()
);

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
 if t.mode not in ('DUO','SQUAD') or captain.mode<>t.mode then raise exception 'La modalidad de tu cuenta no coincide con el torneo.'; end if;
 expected:=case when t.mode='DUO' then 2 else 4 end;
 if coalesce(array_length(teammate_uids,1),0)<>expected-1 then raise exception 'Debes indicar exactamente '||(expected-1)||' UID(s) de compañero(s).'; end if;
 if length(trim(coalesce(team_name,'')))<2 then raise exception 'Escribe un nombre de equipo válido.'; end if;
 select count(*) into used_slots from public.tournament_registrations where tournament_id=t.id and status<>'Cancelado';
 if used_slots>=t.max_slots then raise exception 'El torneo ya alcanzó su cupo máximo.'; end if;
 if exists(select 1 from public.scrim_team_members m join public.scrim_teams st on st.id=m.team_id where m.player_id=captain.id and st.tournament_id=t.id) then raise exception 'Ya perteneces a un equipo de este torneo.'; end if;
 insert into public.scrim_teams(name,mode,captain_id,tournament_id) values(trim(team_name),t.mode,captain.id,t.id) returning id into new_team;
 insert into public.scrim_team_members(team_id,player_id) values(new_team,captain.id);
 foreach uid in array teammate_uids loop
  select * into teammate from public.profiles where game_uid=trim(uid) and mode=t.mode and status='Aprobado';
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
declare inv public.scrim_team_invites%rowtype; tm public.scrim_teams%rowtype; p public.profiles%rowtype; expected integer; current_count integer;
begin
 if auth.uid() is null then raise exception 'Inicia sesión para aceptar la invitación.'; end if;
 select * into inv from public.scrim_team_invites where id=target_invite and invitee_id=auth.uid() for update;
 if not found or inv.status<>'Pendiente' then raise exception 'La invitación no existe o ya fue respondida.'; end if;
 select * into tm from public.scrim_teams where id=inv.team_id for update;
 select * into p from public.profiles where id=auth.uid();
 if p.status<>'Aprobado' or p.mode<>tm.mode then raise exception 'Tu cuenta aprobada debe coincidir con la modalidad del equipo.'; end if;
 if exists(select 1 from public.scrim_team_members m join public.scrim_teams st on st.id=m.team_id where m.player_id=p.id and st.tournament_id=tm.tournament_id) then raise exception 'Ya perteneces a otro equipo en este torneo.'; end if;
 insert into public.scrim_team_members(team_id,player_id) values(tm.id,p.id);
 update public.scrim_team_invites set status='Aceptada' where id=inv.id;
 expected:=case when tm.mode='DUO' then 2 else 4 end;
 select count(*) into current_count from public.scrim_team_members where team_id=tm.id;
 if current_count=expected then
  insert into public.tournament_registrations(tournament_id,team_id) values(tm.tournament_id,tm.id);
 end if;
end;
$$;

revoke all on function public.accept_team_invite(uuid) from public;
grant execute on function public.accept_team_invite(uuid) to authenticated;
