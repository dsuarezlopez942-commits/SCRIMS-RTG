-- SCRIMS RTG · Sistema de notificaciones
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null,
 message text not null,
 kind text not null default 'general',
 link text not null default 'inicio',
 created_at timestamptz not null default now(),
 read_at timestamptz
);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);
alter table public.notifications enable row level security;
grant select on public.notifications to authenticated;
-- Los usuarios solo pueden marcar sus propias notificaciones como leídas.
revoke update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

drop policy if exists "Players read own notifications" on public.notifications;
create policy "Players read own notifications" on public.notifications for select to authenticated using(user_id=auth.uid() or public.is_scrims_admin());
drop policy if exists "Players mark own notifications read" on public.notifications;
create policy "Players mark own notifications read" on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create or replace function public.notify_approved_players(p_title text,p_message text,p_kind text,p_link text)
returns void language sql security definer set search_path=public as $$
 insert into public.notifications(user_id,title,message,kind,link)
 select id,p_title,p_message,p_kind,p_link from public.profiles where status='Aprobado';
$;

-- Esta función solo debe ejecutarse desde triggers internos, nunca como RPC público.
revoke all on function public.notify_approved_players(text,text,text,text) from public, anon, authenticated;

create or replace function public.notify_tournament_events()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='INSERT' then
  if new.status<>'Borrador' then
   perform public.notify_approved_players('Nuevo torneo publicado',new.name||' · Modalidad '||new.mode,'tournament','torneos');
  end if;
 elsif tg_op='UPDATE' then
  if old.registration_open is distinct from new.registration_open then
   perform public.notify_approved_players(case when new.registration_open then 'Inscripciones abiertas' else 'Inscripciones cerradas' end,new.name,'registration','torneos');
  end if;
  if old.status is distinct from new.status and new.status='Finalizado' then
   perform public.notify_approved_players('Torneo finalizado',new.name||' · Ya puedes consultar los resultados.','result','torneos');
  end if;
 end if;
 return new;
end $$;
drop trigger if exists scrims_tournament_notifications on public.tournaments;
create trigger scrims_tournament_notifications after insert or update on public.tournaments for each row execute function public.notify_tournament_events();

create or replace function public.notify_profile_status()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if old.status is distinct from new.status then
  insert into public.notifications(user_id,title,message,kind,link)
  values(new.id,case when new.status='Aprobado' then '¡Cuenta aprobada!' when new.status='Rechazado' then 'Solicitud no aprobada' else 'Estado de cuenta actualizado' end,
  case when new.status='Aprobado' then 'Ya puedes participar en los torneos de SCRIMS RTG.' when new.status='Rechazado' then 'Tu solicitud fue rechazada. Contacta al administrador si necesitas más información.' else 'Tu estado cambió a: '||new.status end,'account','cuenta');
 end if;
 return new;
end $$;
drop trigger if exists scrims_profile_status_notifications on public.profiles;
create trigger scrims_profile_status_notifications after update of status on public.profiles for each row execute function public.notify_profile_status();

create or replace function public.notify_team_invite()
returns trigger language plpgsql security definer set search_path=public as $$
declare t public.scrim_teams%rowtype;
begin
 select * into t from public.scrim_teams where id=new.team_id;
 insert into public.notifications(user_id,title,message,kind,link)
 values(new.invitee_id,'Nueva invitación a equipo','Te invitaron a '||coalesce(t.name,'un equipo')||'. Revisa tus invitaciones.','invite','torneos');
 return new;
end $$;
drop trigger if exists scrims_team_invite_notifications on public.scrim_team_invites;
create trigger scrims_team_invite_notifications after insert on public.scrim_team_invites for each row execute function public.notify_team_invite();

create or replace function public.notify_player_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare tname text;
begin
 select name into tname from public.tournaments where id=new.tournament_id;
 insert into public.notifications(user_id,title,message,kind,link)
 values(new.player_id,'Resultado publicado',coalesce(tname,'Un torneo')||': posición #'||new.placement||', '||new.points||' puntos.','result','clasificacion');
 return new;
end $$;
drop trigger if exists scrims_match_result_notifications on public.match_results;
create trigger scrims_match_result_notifications after insert on public.match_results for each row execute function public.notify_player_result();

create or replace function public.notify_team_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare tname text; teamname text; member record;
begin
 select name into tname from public.tournaments where id=new.tournament_id;
 select name into teamname from public.scrim_teams where id=new.team_id;
 for member in select player_id from public.scrim_team_members where team_id=new.team_id loop
  insert into public.notifications(user_id,title,message,kind,link)
  values(member.player_id,'Resultado de equipo publicado',coalesce(tname,'Un torneo')||' · '||coalesce(teamname,'Tu equipo')||': posición #'||new.placement||', '||new.points||' puntos.','result','clasificacion');
 end loop;
 return new;
end $$;
drop trigger if exists scrims_team_result_notifications on public.team_results;
create trigger scrims_team_result_notifications after insert on public.team_results for each row execute function public.notify_team_result();
