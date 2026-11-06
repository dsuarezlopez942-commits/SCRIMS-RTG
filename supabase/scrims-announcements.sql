-- SCRIMS RTG · Base de datos de avisos globales
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Crea la tabla que utiliza el panel Administrador > Configuración > Avisos globales.
-- No modifica torneos, jugadores, inscripciones ni resultados existentes.

create table if not exists public.scrims_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 90),
  message text not null check (char_length(trim(message)) between 1 and 1200),
  level text not null default 'important'
    check (level in ('important', 'urgent', 'info')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists scrims_announcements_active_created_idx
  on public.scrims_announcements(active, created_at desc);

alter table public.scrims_announcements enable row level security;

drop policy if exists "Anyone can read active SCRIMS announcements" on public.scrims_announcements;
create policy "Anyone can read active SCRIMS announcements"
  on public.scrims_announcements for select
  to anon, authenticated
  using (active = true or (
    auth.uid() is not null and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  ));

drop policy if exists "SCRIMS admins can publish announcements" on public.scrims_announcements;
create policy "SCRIMS admins can publish announcements"
  on public.scrims_announcements for insert
  to authenticated
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ));

drop policy if exists "SCRIMS admins can update announcements" on public.scrims_announcements;
create policy "SCRIMS admins can update announcements"
  on public.scrims_announcements for update
  to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ));

grant select on public.scrims_announcements to anon, authenticated;
grant insert, update on public.scrims_announcements to authenticated;

-- Habilitar eventos Realtime para que los avisos nuevos se reflejen sin recargar.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'scrims_announcements'
  ) then
    alter publication supabase_realtime add table public.scrims_announcements;
  end if;
exception
  when undefined_object then
    raise notice 'La publicación supabase_realtime no existe; Realtime se puede habilitar desde Database > Publications.';
end
$$;
