-- SCRIMS RTG / Creative Destruction
-- Ejecuta este archivo completo en Supabase > SQL Editor > New query.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  game_uid text not null unique,
  mode text not null check (mode in ('SOLO','DUO','SQUAD')),
  team_name text,
  status text not null default 'Pendiente' check (status in ('Pendiente','Aprobado','Rechazado')),
  role text not null default 'player' check (role in ('player','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mode text not null check (mode in ('SOLO','DUO','SQUAD')),
  status text not null default 'Abierto' check (status in ('Borrador','Abierto','Finalizado')),
  starts_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.match_results (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  placement integer not null default 0 check (placement >= 0),
  kills integer not null default 0 check (kills >= 0),
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default now(),
  unique (tournament_id, player_id)
);

create or replace function public.is_scrims_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

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
    coalesce(new.raw_user_meta_data->>'mode', 'SOLO'),
    nullif(new.raw_user_meta_data->>'team_name', '')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_scrims on auth.users;
create trigger on_auth_user_created_scrims
after insert on auth.users
for each row execute procedure public.handle_new_scrims_user();

alter table public.profiles enable row level security;
alter table public.tournaments enable row level security;
alter table public.match_results enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.tournaments, public.match_results to anon, authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.tournaments, public.match_results to authenticated;
grant execute on function public.is_scrims_admin() to anon, authenticated;

drop policy if exists "Approved profiles and own profile are visible" on public.profiles;
create policy "Approved profiles and own profile are visible"
on public.profiles for select
to anon, authenticated
using (status = 'Aprobado' or id = auth.uid() or public.is_scrims_admin());

drop policy if exists "Only admins can update profiles" on public.profiles;
create policy "Only admins can update profiles"
on public.profiles for update
to authenticated
using (public.is_scrims_admin())
with check (public.is_scrims_admin());

drop policy if exists "Public can view non-draft tournaments" on public.tournaments;
create policy "Public can view non-draft tournaments"
on public.tournaments for select
to anon, authenticated
using (status <> 'Borrador' or public.is_scrims_admin());

drop policy if exists "Admins manage tournaments" on public.tournaments;
create policy "Admins manage tournaments"
on public.tournaments for all
to authenticated
using (public.is_scrims_admin())
with check (public.is_scrims_admin());

drop policy if exists "Public can view results of approved players" on public.match_results;
create policy "Public can view results of approved players"
on public.match_results for select
to anon, authenticated
using (
  public.is_scrims_admin()
  or exists (
    select 1 from public.profiles p
    where p.id = match_results.player_id and p.status = 'Aprobado'
  )
);

drop policy if exists "Admins manage results" on public.match_results;
create policy "Admins manage results"
on public.match_results for all
to authenticated
using (public.is_scrims_admin())
with check (public.is_scrims_admin());

-- IMPORTANTE: después de registrar tu cuenta en la web, cambia TU_CORREO aquí
-- y ejecuta esta instrucción aparte para convertir tu usuario en administrador:
-- update public.profiles p
-- set role = 'admin'
-- from auth.users u
-- where p.id = u.id and u.email = 'TU_CORREO';
