# SCRIMS RTG — CUBEX POINTS MANAGER

Plataforma para scrims y torneos de **Creative Destruction**.

## Estado del proyecto

- `index.html`: primera interfaz visual de demostración (todavía no conectada a datos compartidos).
- `config.js`: configuración pública pendiente de completar con la URL del proyecto Supabase y su clave anon/publishable.
- `supabase/schema.sql`: esquema inicial de base de datos, registro de jugadores, torneos, resultados y políticas RLS.

**No publicar ni distribuir la interfaz actual como plataforma multiusuario todavía.** El siguiente paso es crear el proyecto Supabase, ejecutar el SQL, y luego conectar la interfaz con Supabase Auth y la base de datos. No contiene ni debe contener una clave `service_role`.

## Configuración pendiente

1. Crear un proyecto Supabase Free.
2. Abrir el SQL Editor y ejecutar `supabase/schema.sql`.
3. Completar `config.js` con Project URL y la clave pública anon/publishable.
4. Registrar la cuenta del propietario desde la web.
5. Promover esa cuenta a administradora ejecutando en SQL Editor el UPDATE comentado al final de `supabase/schema.sql`, sustituyendo `TU_CORREO` por el correo usado para registrarse.
6. Conectar este repositorio a Cloudflare Pages para publicar el sitio.

## Seguridad

- No guardar contraseñas de jugadores en tablas propias; Supabase Auth administra las credenciales.
- Nunca colocar una clave `service_role` en archivos del frontend.
- Las tablas usan Row Level Security (RLS); revisar las políticas antes de añadir nuevas funciones.
- El rol administrador se asigna manualmente desde SQL, nunca desde el formulario público.
