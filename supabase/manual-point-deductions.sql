-- SCRIMS RTG · Descuentos manuales de puntos
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- No modifica ni elimina resultados, kills, torneos o inscripciones.

create table if not exists public.point_deductions (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  player_id uuid references public.profiles(id) on delete cascade,
  team_id uuid references public.scrim_teams(id) on delete cascade,
  points integer not null check (points > 0 and points <= 1000000),
  reason text not null check (char_length(trim(reason)) >= 1 and char_length(reason) <= 300),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint point_deductions_one_target check (
    (player_id is not null and team_id is null)
    or (player_id is null and team_id is not null)
  )
);

create index if not exists point_deductions_player_idx
  on public.point_deductions(player_id, created_at desc);
create index if not exists point_deductions_team_idx
  on public.point_deductions(team_id, created_at desc);
create index if not exists point_deductions_tournament_idx
  on public.point_deductions(tournament_id, created_at desc);

alter table public.point_deductions enable row level security;

drop policy if exists "Admins can view point deductions" on public.point_deductions;
create policy "Admins can view point deductions"
  on public.point_deductions for select
  to authenticated
  using (public.is_scrims_admin());

drop policy if exists "Admins can create point deductions" on public.point_deductions;
create policy "Admins can create point deductions"
  on public.point_deductions for insert
  to authenticated
  with check (public.is_scrims_admin() and created_by = auth.uid());

drop policy if exists "Admins can cancel point deductions" on public.point_deductions;
create policy "Admins can cancel point deductions"
  on public.point_deductions for delete
  to authenticated
  using (public.is_scrims_admin());

grant select, insert, delete on public.point_deductions to authenticated;
