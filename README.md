# SCRIMS RTG — CUBEX POINTS MANAGER

Plataforma web para scrims y torneos de **Creative Destruction**.

## Estado

- `index.html`: interfaz conectada a Supabase Auth y a las tablas de perfiles, torneos y resultados.
- `config.js`: URL del proyecto y publishable key pública de Supabase.
- `supabase/schema.sql`: esquema PostgreSQL y políticas Row Level Security (RLS).

## Publicación pendiente

El sitio todavía debe desplegarse en un hosting estático, por ejemplo Cloudflare Pages, conectado al repositorio GitHub.

## Primer administrador

1. Publica el sitio y abre su URL.
2. Registra una cuenta con el correo que será administrador.
3. Confirma el correo y entra a la plataforma.
4. En Supabase > SQL Editor ejecuta esta consulta, sustituyendo el correo si corresponde:

```sql
update public.profiles p
set role = 'admin'
from auth.users u
where p.id = u.id
  and u.email = 'dsuarezlopez942@gmail.com';
```

5. Cierra sesión y vuelve a iniciar sesión para que la aplicación detecte el rol actualizado.

El rol nunca se asigna desde el formulario público.

## Reglas de puntuación

- SOLO: puntos por posición según la tabla incorporada en la aplicación y 2 puntos por kill hasta 10 kills.
- DUO y SQUAD: puntos manuales hasta que el organizador confirme sus reglas.

## Seguridad

- Las contraseñas se gestionan mediante Supabase Auth; la aplicación no almacena contraseñas propias.
- La publishable key es pública y está diseñada para el navegador.
- Nunca colocar una secret key ni una service_role key en el frontend.
- Las tablas están protegidas mediante RLS. Revisar las políticas antes de ampliar permisos.
