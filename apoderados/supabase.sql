-- Tabla de apoderados
-- Pegar completo en Supabase → SQL Editor → Run

create table if not exists public.apoderados (
  id              bigint generated always as identity primary key,
  nombre_apoderado text not null check (char_length(trim(nombre_apoderado)) between 3 and 120),
  nombre_hijo      text not null check (char_length(trim(nombre_hijo)) between 2 and 120),
  telefono         text not null check (telefono ~ '^\+?[0-9]{8,15}$'),
  correo           text check (correo is null or correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  creado_en        timestamptz not null default now()
);

-- Seguridad: el público solo puede INSERTAR, nunca leer, editar ni borrar
alter table public.apoderados enable row level security;

drop policy if exists "publico_puede_insertar" on public.apoderados;
create policy "publico_puede_insertar"
  on public.apoderados
  for insert
  to anon
  with check (true);

revoke select, update, delete on public.apoderados from anon;
grant insert on public.apoderados to anon;
