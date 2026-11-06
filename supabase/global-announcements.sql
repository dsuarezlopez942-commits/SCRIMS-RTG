-- SCRIMS RTG · Avisos globales persistentes
-- Ejecutar en Supabase > SQL Editor después de schema.sql.
create table if not exists public.scrims_announcements (
 id uuid primary key default gen_random_uuid(),
 title text not null check (char_length(trim(title)) between 1 and 90),
 message text not null check (char_length(trim(message)) between 1 and 1200),
 level text not null default 'important' check (level in ('info','important','urgent')),
 active boolean not null default true,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists scrims_announcements_active_created_idx on public.scrims_announcements(active,created_at desc);
alter table public.scrims_announcements enable row level security;
grant select on public.scrims_announcements to anon,authenticated;
grant insert,update,delete on public.scrims_announcements to authenticated;
drop policy if exists "Anyone can read active SCRIMS announcements" on public.scrims_announcements;
create policy "Anyone can read active SCRIMS announcements" on public.scrims_announcements for select to anon,authenticated using(active or public.is_scrims_admin());
drop policy if exists "Only SCRIMS admins create announcements" on public.scrims_announcements;
create policy "Only SCRIMS admins create announcements" on public.scrims_announcements for insert to authenticated with check(public.is_scrims_admin() and (created_by is null or created_by=auth.uid()));
drop policy if exists "Only SCRIMS admins update announcements" on public.scrims_announcements;
create policy "Only SCRIMS admins update announcements" on public.scrims_announcements for update to authenticated using(public.is_scrims_admin()) with check(public.is_scrims_admin());
drop policy if exists "Only SCRIMS admins delete announcements" on public.scrims_announcements;
create policy "Only SCRIMS admins delete announcements" on public.scrims_announcements for delete to authenticated using(public.is_scrims_admin());
do $$ begin
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='scrims_announcements') then
  alter publication supabase_realtime add table public.scrims_announcements;
 end if;
end $$;