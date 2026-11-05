-- SCRIMS RTG · Administración de administradores
-- Ejecutar una sola vez en Supabase > SQL Editor > New query.
-- Requiere que supabase/schema.sql ya esté aplicado.

create or replace function public.set_scrims_admin_role(
  target_profile uuid,
  make_admin boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.profiles%rowtype;
  admin_count integer;
begin
  if auth.uid() is null or not public.is_scrims_admin() then
    raise exception 'No tienes permisos para administrar roles.';
  end if;

  if make_admin is null then
    raise exception 'Debes indicar si deseas asignar o retirar el rol.';
  end if;

  -- Serializa cambios de roles para evitar que dos acciones simultáneas
  -- retiren accidentalmente todos los administradores.
  perform pg_advisory_xact_lock(hashtext('scrims-rtg-admin-role-management'));

  select * into target
  from public.profiles
  where id = target_profile
  for update;

  if not found then
    raise exception 'No se encontró el perfil seleccionado.';
  end if;

  if target.id = auth.uid() then
    raise exception 'No puedes modificar tu propio rol administrativo.';
  end if;

  if make_admin then
    if target.status <> 'Aprobado' then
      raise exception 'Solo puedes convertir en administrador a un jugador aprobado.';
    end if;

    update public.profiles
    set role = 'admin'
    where id = target.id and role <> 'admin';
  else
    if target.role <> 'admin' then
      raise exception 'Este usuario no tiene el rol de administrador.';
    end if;

    select count(*) into admin_count
    from public.profiles
    where role = 'admin';

    if admin_count <= 1 then
      raise exception 'No puedes retirar el último administrador de SCRIMS RTG.';
    end if;

    update public.profiles
    set role = 'player'
    where id = target.id;
  end if;
end;
$$;

revoke all on function public.set_scrims_admin_role(uuid, boolean) from public, anon;
grant execute on function public.set_scrims_admin_role(uuid, boolean) to authenticated;
