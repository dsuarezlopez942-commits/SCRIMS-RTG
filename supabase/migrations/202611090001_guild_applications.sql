-- SCRIMS RTG · Solicitudes para el único gremio ROAD TO GLORY
create table if not exists public.guild_applications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 nickname text not null,
 game_uid text not null,
 country text not null,
 age integer not null check (age between 13 and 99),
 experience text not null default '',
 socials text not null default '',
 message text not null,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 admin_note text,
 media jsonb not null default '[]'::jsonb,
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists guild_applications_user_created_idx on public.guild_applications(user_id,created_at desc);
create index if not exists guild_applications_status_created_idx on public.guild_applications(status,created_at desc);
alter table public.guild_applications enable row level security;
drop policy if exists "Applicants read own guild applications" on public.guild_applications;
create policy "Applicants read own guild applications" on public.guild_applications for select to authenticated
using (auth.uid()=user_id or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "Applicants create own guild applications" on public.guild_applications;
create policy "Applicants create own guild applications" on public.guild_applications for insert to authenticated
with check (auth.uid()=user_id and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "Admins update guild applications" on public.guild_applications;
create policy "Admins update guild applications" on public.guild_applications for update to authenticated
using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('guild-applications','guild-applications',false,31457280,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public=false,file_size_limit=31457280,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Applicants upload own guild media" on storage.objects;
create policy "Applicants upload own guild media" on storage.objects for insert to authenticated
with check (bucket_id='guild-applications' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Applicants and admins read guild media" on storage.objects;
create policy "Applicants and admins read guild media" on storage.objects for select to authenticated
using (bucket_id='guild-applications' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')));
drop policy if exists "Applicants delete own guild media" on storage.objects;
create policy "Applicants delete own guild media" on storage.objects for delete to authenticated
using (bucket_id='guild-applications' and (storage.foldername(name))[1]=auth.uid()::text);
