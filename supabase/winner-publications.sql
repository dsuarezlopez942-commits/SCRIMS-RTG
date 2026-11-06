-- SCRIMS RTG · Publicación de ganadores y Top 5
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- No modifica ni elimina torneos, inscripciones ni resultados existentes.

create table if not exists public.tournament_winner_posts (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id),
  mode text not null check (mode in ('SOLO','DUO','SQUAD')),
  title text not null,
  content text,
  image_url text,
  top5 jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists tournament_winner_posts_tournament_created_idx
  on public.tournament_winner_posts(tournament_id, created_at desc);

alter table public.tournament_winner_posts enable row level security;

drop policy if exists "Winner posts are public" on public.tournament_winner_posts;
create policy "Winner posts are public"
  on public.tournament_winner_posts for select
  to anon, authenticated
  using (true);

drop policy if exists "Admins can publish winner posts" on public.tournament_winner_posts;
create policy "Admins can publish winner posts"
  on public.tournament_winner_posts for insert
  to authenticated
  with check (public.is_scrims_admin() and created_by = auth.uid());

drop policy if exists "Admins can delete winner posts" on public.tournament_winner_posts;
create policy "Admins can delete winner posts"
  on public.tournament_winner_posts for delete
  to authenticated
  using (public.is_scrims_admin());

-- Bucket público para mostrar las capturas en el leaderboard.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('scrims-winner-results', 'scrims-winner-results', true, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public can view winner result images" on storage.objects;
create policy "Public can view winner result images"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'scrims-winner-results');

drop policy if exists "Admins can upload winner result images" on storage.objects;
create policy "Admins can upload winner result images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'scrims-winner-results' and public.is_scrims_admin());

drop policy if exists "Admins can delete winner result images" on storage.objects;
create policy "Admins can delete winner result images"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'scrims-winner-results' and public.is_scrims_admin());

grant select on public.tournament_winner_posts to anon, authenticated;
grant insert, delete on public.tournament_winner_posts to authenticated;
