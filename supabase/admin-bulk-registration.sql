-- SCRIMS RTG · Inscripción masiva administrada
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- No elimina ni modifica inscripciones, equipos o resultados existentes.

create or replace function public.admin_bulk_register_tournament(target_tournament uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.tournaments%rowtype;
  used_slots integer := 0;
  available_slots integer := 0;
  team_size integer := 1;
  candidate_ids uuid[];
  eligible_count integer := 0;
  inserted_count integer := 0;
  teams_created integer := 0;
  remaining_count integer := 0;
  team_no integer := 0;
  new_team uuid;
  group_ids uuid[];
begin
  if auth.uid() is null or not public.is_scrims_admin() then
    raise exception 'Solo los administradores pueden ejecutar inscripciones masivas.';
  end if;

  select * into t
  from public.tournaments
  where id = target_tournament
  for update;

  if not found then raise exception 'No se encontró el torneo.'; end if;
  if t.status <> 'Abierto' or not t.registration_open
     or (t.registration_closes_at is not null and now() > t.registration_closes_at) then
    raise exception 'El torneo debe estar abierto y dentro del plazo de inscripción.';
  end if;

  select count(*) into used_slots
  from public.tournament_registrations
  where tournament_id = t.id and status <> 'Cancelado';

  available_slots := greatest(coalesce(t.max_slots,100) - used_slots, 0);

  if t.mode = 'SOLO' then
    -- Reactiva filas canceladas existentes antes de insertar nuevas,
    -- respetando los cupos y el índice único histórico.
    with to_reactivate as (
      select r.id
      from public.tournament_registrations r
      join public.profiles p on p.id = r.player_id
      where r.tournament_id = t.id
        and r.status = 'Cancelado'
        and p.status = 'Aprobado'
        and not public.is_player_banned(p.id)
      order by r.created_at, p.nickname
      limit available_slots
    ), reactivated as (
      update public.tournament_registrations r
      set status = 'Inscrito'
      from to_reactivate x
      where r.id = x.id
      returning r.id
    )
    select count(*) into inserted_count from reactivated;

    select count(*) into eligible_count
    from public.profiles p
    where p.status = 'Aprobado'
      and not public.is_player_banned(p.id);

    if available_slots > inserted_count then
      insert into public.tournament_registrations(tournament_id, player_id)
      select t.id, p.id
      from public.profiles p
      where p.status = 'Aprobado'
        and not public.is_player_banned(p.id)
        and not exists (
          select 1 from public.tournament_registrations r
          where r.tournament_id = t.id and r.player_id = p.id
        )
      order by p.created_at, p.nickname
      limit (available_slots - inserted_count)
      on conflict (tournament_id, player_id)
      where player_id is not null
      do nothing;
      get diagnostics team_no = row_count;
      inserted_count := inserted_count + team_no;
    end if;

    return jsonb_build_object(
      'mode', t.mode,
      'registered', inserted_count,
      'teams_created', 0,
      'already_or_ineligible', greatest(eligible_count - inserted_count, 0),
      'remaining_unteamed', 0,
      'slots_left', greatest(available_slots - inserted_count, 0)
    );
  end if;

  team_size := case when t.mode = 'DUO' then 2 else 4 end;

  select coalesce(array_agg(p.id order by p.created_at, p.nickname), array[]::uuid[])
  into candidate_ids
  from public.profiles p
  where p.status = 'Aprobado'
    and not public.is_player_banned(p.id)
    and not exists (
      select 1 from public.tournament_registrations r
      where r.tournament_id = t.id and r.status <> 'Cancelado'
        and r.player_id = p.id
    )
    and not exists (
      select 1
      from public.scrim_team_members m
      join public.scrim_teams st on st.id = m.team_id
      where m.player_id = p.id and st.tournament_id = t.id
    )
    and not exists (
      select 1 from public.tournament_registrations r
      where r.tournament_id = t.id and r.player_id = p.id
    );

  eligible_count := cardinality(candidate_ids);
  available_slots := least(available_slots, 1000);

  if available_slots > 0 and eligible_count >= team_size then
    for team_no in 1..least(available_slots, eligible_count / team_size) loop
      group_ids := candidate_ids[((team_no - 1) * team_size + 1):(team_no * team_size)];

      insert into public.scrim_teams(name, mode, captain_id, tournament_id)
      values (
        'AUTO-' || upper(substr(replace(t.id::text, '-', ''), 1, 6)) || '-' || t.mode || '-' || lpad(team_no::text, 3, '0'),
        t.mode,
        group_ids[1],
        t.id
      )
      returning id into new_team;

      insert into public.scrim_team_members(team_id, player_id)
      select new_team, member_id from unnest(group_ids) as member_id;

      insert into public.tournament_registrations(tournament_id, team_id)
      values (t.id, new_team);

      teams_created := teams_created + 1;
    end loop;
  end if;

  inserted_count := teams_created * team_size;
  remaining_count := greatest(eligible_count - inserted_count, 0);

  return jsonb_build_object(
    'mode', t.mode,
    'registered', inserted_count,
    'teams_created', teams_created,
    'already_or_ineligible', 0,
    'remaining_unteamed', remaining_count,
    'slots_left', greatest(available_slots - teams_created, 0)
  );
end;
$$;

revoke all on function public.admin_bulk_register_tournament(uuid) from public, anon;
grant execute on function public.admin_bulk_register_tournament(uuid) to authenticated;
