-- SCRIMS RTG: equipos independientes de torneos
-- Ejecutar una sola vez en Supabase > SQL Editor > New query.

create or replace function public.get_team_hub()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_data jsonb;
begin
 if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
 select jsonb_build_object(
  'teams', coalesce((
   select jsonb_agg(jsonb_build_object(
    'id',t.id,'name',t.name,'mode',t.mode,'captain_id',t.captain_id,'tournament_id',t.tournament_id,
    'members',coalesce((select jsonb_agg(jsonb_build_object('player_id',m.player_id,'nickname',p.nickname,'game_uid',p.game_uid,'joined_at',m.joined_at) order by m.joined_at)
      from scrim_team_members m left join profiles p on p.id=m.player_id where m.team_id=t.id),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'invitee_id',i.invitee_id,'nickname',p.nickname,'game_uid',p.game_uid,'status',i.status,'created_at',i.created_at) order by i.created_at desc)
      from scrim_team_invites i left join profiles p on p.id=i.invitee_id where i.team_id=t.id and i.status='Pendiente'),'[]'::jsonb)
   ) order by t.created_at desc)
   from scrim_teams t where t.tournament_id is null and (t.captain_id=v_uid or exists(select 1 from scrim_team_members m where m.team_id=t.id and m.player_id=v_uid))
  ),'[]'::jsonb),
  'incoming',coalesce((
   select jsonb_agg(jsonb_build_object('id',i.id,'team_id',t.id,'team_name',t.name,'mode',t.mode,'captain_id',t.captain_id,'captain_name',cp.nickname,'created_at',i.created_at) order by i.created_at desc)
   from scrim_team_invites i join scrim_teams t on t.id=i.team_id left join profiles cp on cp.id=t.captain_id
   where i.invitee_id=v_uid and i.status='Pendiente' and t.tournament_id is null
  ),'[]'::jsonb)
 ) into v_data;
 return v_data;
end;
$$;

create or replace function public.create_standalone_team(team_name text, team_mode text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_profile profiles%rowtype;
begin
 if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
 select * into v_profile from profiles where id=v_uid;
 if not found or v_profile.status <> 'Aprobado' then raise exception 'Tu cuenta debe estar aprobada para crear equipos.'; end if;
 if upper(team_mode) not in ('DUO','SQUAD') then raise exception 'La modalidad debe ser DUO o SQUAD.'; end if;
 if length(trim(coalesce(team_name,''))) < 2 then raise exception 'El nombre debe tener al menos 2 caracteres.'; end if;
 if exists(select 1 from scrim_team_members where player_id=v_uid) then raise exception 'Ya perteneces a un equipo. Sal de tu equipo actual antes de crear otro.'; end if;
 insert into scrim_teams(name,mode,captain_id,tournament_id) values(trim(team_name),upper(team_mode),v_uid,null) returning id into v_id;
 insert into scrim_team_members(team_id,player_id) values(v_id,v_uid);
 return v_id;
end;
$$;

create or replace function public.invite_player_to_team(target_team uuid, target_player uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_team scrim_teams%rowtype; v_profile profiles%rowtype; v_count int;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
 select * into v_team from scrim_teams where id=target_team and tournament_id is null;
 if not found or v_team.captain_id <> auth.uid() then raise exception 'Solo el capitán puede invitar jugadores.'; end if;
 select * into v_profile from profiles where id=target_player and status='Aprobado';
 if not found then raise exception 'No se encontró un jugador aprobado.'; end if;
 if target_player=auth.uid() then raise exception 'No puedes invitarte a ti mismo.'; end if;
 select count(*) into v_count from scrim_team_members where team_id=target_team;
 if v_count >= case when v_team.mode='DUO' then 2 else 4 end then raise exception 'El equipo ya está completo.'; end if;
 if exists(select 1 from scrim_team_members where player_id=target_player) then raise exception 'Ese jugador ya pertenece a un equipo.'; end if;
 if exists(select 1 from scrim_team_invites where team_id=target_team and invitee_id=target_player and status='Pendiente') then raise exception 'Ya existe una invitación pendiente para ese jugador.'; end if;
 insert into scrim_team_invites(team_id,invitee_id,status) values(target_team,target_player,'Pendiente');
end;
$$;

create or replace function public.respond_standalone_team_invite(target_invite uuid, accept_invite boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_inv scrim_team_invites%rowtype; v_team scrim_teams%rowtype; v_count int;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
 select * into v_inv from scrim_team_invites where id=target_invite and invitee_id=auth.uid() and status='Pendiente' for update;
 if not found then raise exception 'La invitación ya no está disponible.'; end if;
 select * into v_team from scrim_teams where id=v_inv.team_id and tournament_id is null;
 if not found then raise exception 'El equipo ya no está disponible.'; end if;
 if accept_invite then
  if exists(select 1 from scrim_team_members where player_id=auth.uid()) then raise exception 'Ya perteneces a un equipo.'; end if;
  select count(*) into v_count from scrim_team_members where team_id=v_team.id;
  if v_count >= case when v_team.mode='DUO' then 2 else 4 end then raise exception 'El equipo ya está completo.'; end if;
  insert into scrim_team_members(team_id,player_id) values(v_team.id,auth.uid());
  update scrim_team_invites set status='Aceptada' where id=target_invite;
 else
  update scrim_team_invites set status='Rechazada' where id=target_invite;
 end if;
end;
$$;

grant execute on function public.get_team_hub() to authenticated;
grant execute on function public.create_standalone_team(text,text) to authenticated;
grant execute on function public.invite_player_to_team(uuid,uuid) to authenticated;
grant execute on function public.respond_standalone_team_invite(uuid,boolean) to authenticated;
