-- Store each player's registration email in their own profile row.
-- Backfill existing accounts from Supabase Auth and keep it synchronized.
alter table public.profiles add column if not exists email text;

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id
  and (p.email is distinct from u.email);

create or replace function public.sync_scrims_profile_email()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update public.profiles
  set email = new.email
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists sync_scrims_profile_email on auth.users;
create trigger sync_scrims_profile_email
after update of email on auth.users
for each row execute function public.sync_scrims_profile_email();

-- The admin panel reads the email through its existing profiles SELECT policy.
