-- SCRIMS RTG · Sistema de baneos administrado
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor.
-- No modifica ni elimina perfiles, puntos o resultados existentes.

create table if not exists public.scrims_player_bans (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (length(trim(reason)) between 5 and 1000),
  evidence_url text,
  banned_by uuid not null references public.profiles(id),
  banned_at timestamptz not null default now(),
  expires_at timestamptz,
  lifted_at timestamptz,
  lifted_by uuid references public.profiles(id),
  lift_note text,
  constraint valid_ban_expiry check (expires_at is null or expires_at > banned_at)
);

create index if not exists scrims_player_bans_player_active_idx
on public.scrims_player_bans(player_id, expires_at)
where lifted_at is null;

alter table public.scrims_player_bans enable row level security;
grant select, insert, update on public.scrims_player_bans to authenticated;

drop policy if exists "Admins manage player bans" on public.scrims_player_bans;
create policy "Admins manage player bans"
on public.scrims_player_bans
for all to authenticated
using (public.is_scrims_admin())
with check (public.is_scrims_admin());

create or replace function public.is_player_banned(target_player uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.scrims_player_bans b
    where b.player_id = target_player
      and b.lifted_at is null
      and (b.expires_at is null or b.expires_at > now())
  );
$$;
revoke all on function public.is_player_banned(uuid) from public, anon, authenticated;

create or replace function public.get_my_ban_status()
returns table(is_banned boolean, reason text, expires_at timestamptz)
language sql stable security definer
set search_path = public
as $$
  select true, b.reason, b.expires_at
  from public.scrims_player_bans b
  where b.player_id = auth.uid()
    and b.lifted_at is null
    and (b.expires_at is null or b.expires_at > now())
  order by b.banned_at desc
  limit 1;
$$;
revoke all on function public.get_my_ban_status() from public, anon;
grant execute on function public.get_my_ban_status() to authenticated;

create or replace function public.admin_ban_player(
  target_player uuid,
  ban_reason text,
  evidence_url text default null,
  ban_expires_at timestamptz default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare new_ban_id uuid; target_role text;
begin
  if auth.uid() is null or not public.is_scrims_admin() then
    raise exception 'Solo los administradores pueden aplicar baneos.';
  end if;
  if target_player is null or target_player = auth.uid() then
    raise exception 'No puedes banear tu propia cuenta.';
  end if;
  if length(trim(coalesce(ban_reason,''))) < 5 then
    raise exception 'Escribe un motivo de al menos 5 caracteres.';
  end if;
  if ban_expires_at is not null and ban_expires_at <= now() then
    raise exception 'La fecha de finalización debe estar en el futuro.';
  end if;
  select role into target_role from public.profiles where id=target_player;
  if not found then raise exception 'No se encontró al jugador.'; end if;
  if target_role = 'admin' then raise exception 'No se puede banear a otro administrador desde este sistema.'; end if;

  update public.scrims_player_bans
    set lifted_at=now(), lifted_by=auth.uid(), lift_note='Reemplazado por una nueva sanción'
    where player_id=target_player and lifted_at is null
      and (expires_at is null or expires_at > now());

  insert into public.scrims_player_bans(player_id,reason,evidence_url,banned_by,expires_at)
  values(target_player,trim(ban_reason),nullif(trim(coalesce(evidence_url,'')),''),auth.uid(),ban_expires_at)
  returning id into new_ban_id;

  -- Retira al jugador de inscripciones individuales y cancela la inscripción
  -- del equipo si forma parte de él, conservando el historial.
  update public.tournament_registrations
    set status='Cancelado'
    where status <> 'Cancelado'
      and player_id=target_player;

  update public.tournament_registrations r
    set status='Cancelado'
    where r.status <> 'Cancelado'
      and r.team_id in (select m.team_id from public.scrim_team_members m where m.player_id=target_player);

  update public.scrim_team_invites
    set status='Rechazada'
    where invitee_id=target_player and status='Pendiente';

  return new_ban_id;
end;
$$;
revoke all on function public.admin_ban_player(uuid,text,text,timestamptz) from public, anon;
grant execute on function public.admin_ban_player(uuid,text,text,timestamptz) to authenticated;

create or replace function public.admin_lift_player_ban(target_ban uuid, note text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_scrims_admin() then
    raise exception 'Solo los administradores pueden levantar baneos.';
  end if;
  update public.scrims_player_bans
    set lifted_at=now(), lifted_by=auth.uid(), lift_note=nullif(trim(coalesce(note,'')),'')
    where id=target_ban and lifted_at is null;
  if not found then raise exception 'El baneo no existe o ya fue levantado.'; end if;
end;
$$;
revoke all on function public.admin_lift_player_ban(uuid,text) from public, anon;
grant execute on function public.admin_lift_player_ban(uuid,text) to authenticated;

-- Bloqueo a nivel de base de datos: no se puede inscribir ni aceptar
-- invitaciones de equipo mientras exista un baneo activo.
create or replace function public.block_banned_player_participation()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare target_player uuid;
begin
  if tg_table_name = 'tournament_registrations' then
    if new.player_id is not null then
      target_player := new.player_id;
    elsif new.team_id is not null then
      if exists (
        select 1 from public.scrim_team_members m
        where m.team_id=new.team_id and public.is_player_banned(m.player_id)
      ) then
        raise exception 'El equipo contiene un jugador baneado y no puede participar.';
      end if;
    end if;
  elsif tg_table_name = 'scrim_team_members' then
    target_player := new.player_id;
  end if;

  if target_player is not null and public.is_player_banned(target_player) then
    raise exception 'Tu cuenta está baneada y no puede participar en torneos.';
  end if;
  return new;
end;
$$;

drop trigger if exists block_banned_player_registration on public.tournament_registrations;
create trigger block_banned_player_registration
before insert or update of player_id, team_id, status
on public.tournament_registrations
for each row when (new.status <> 'Cancelado')
execute function public.block_banned_player_participation();

drop trigger if exists block_banned_team_member on public.scrim_team_members;
create trigger block_banned_team_member
before insert or update of player_id, team_id
on public.scrim_team_members
for each row
execute function public.block_banned_player_participation();

-- El historial solo lo pueden consultar los administradores.
