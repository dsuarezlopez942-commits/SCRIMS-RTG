-- SCRIMS RTG: avatar de jugadores
-- Ejecuta este archivo UNA SOLA VEZ en Supabase > SQL Editor > New query.

alter table public.profiles
add column if not exists avatar_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('player-avatars', 'player-avatars', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = true,
  file_size_limit = 3145728,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Public can view player avatars" on storage.objects;
create policy "Public can view player avatars"
on storage.objects for select
to public
using (bucket_id = 'player-avatars');

drop policy if exists "Players upload own avatar" on storage.objects;
create policy "Players upload own avatar"
on storage.objects for insert
to authenticated
with check (bucket_id = 'player-avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Players update own avatar" on storage.objects;
create policy "Players update own avatar"
on storage.objects for update
to authenticated
using (bucket_id = 'player-avatars' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'player-avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Players delete own avatar" on storage.objects;
create policy "Players delete own avatar"
on storage.objects for delete
to authenticated
using (bucket_id = 'player-avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function public.set_my_avatar_url(new_avatar_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if new_avatar_url is null or new_avatar_url !~ '^https://[^/]+/storage/v1/object/public/player-avatars/' then
    raise exception 'URL de avatar no válida.';
  end if;
  update public.profiles
  set avatar_url = new_avatar_url
  where id = auth.uid();
end;
$$;

revoke all on function public.set_my_avatar_url(text) from public;
grant execute on function public.set_my_avatar_url(text) to authenticated;
