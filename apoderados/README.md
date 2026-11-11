# Formulario de apoderados — puesta en marcha (gratis)

## 1. Base de datos (Supabase)
1. Crea una cuenta en https://supabase.com y un proyecto nuevo (región: São Paulo).
2. Ve a **SQL Editor**, pega el contenido de `supabase.sql` y presiona **Run**.
3. Ve a **Project Settings → API** y copia:
   - **Project URL**
   - **anon / publishable key** (NUNCA la `service_role` / secret key)

## 2. Configura el formulario (secretos de GitHub)
En el repo: **Settings → Secrets and variables → Actions → New repository secret**:
- `SUPABASE_URL`
- `SUPABASE_KEY` (anon/publishable)

Y en **Settings → Pages → Build and deployment → Source** elige **GitHub Actions**.
El workflow `.github/workflows/pages.yml` reemplaza `__SUPABASE_URL__` y `__SUPABASE_KEY__` al publicar.
La clave queda visible en la página publicada (así funciona cualquier frontend); por eso solo se usa la clave pública.

## 3. Publicación (GitHub Pages)
El formulario vive en https://cmonroy2022.github.io/apoderados/
Cada push a `main` lo actualiza en 1–2 minutos.

## 4. Ver los registros
Supabase → **Table Editor → apoderados**. Desde ahí puedes exportar a CSV.

## Seguridad
- El público solo puede **insertar**; nadie puede leer los datos con la key pública.
- La base valida largo de nombres, formato de teléfono y correo.

## Ojo con el plan gratis
Supabase pausa los proyectos gratis tras 7 días sin actividad. Si el formulario pasa una semana
sin uso, entra al panel y presiona "Restore". Se puede evitar con un ping semanal (cron / GitHub Actions).
