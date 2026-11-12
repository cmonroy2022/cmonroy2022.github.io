-- Ficha de apoderados: Jardín Infantil Los Folkloristas
-- Pegar COMPLETO en Supabase → SQL Editor → Run.
-- Se puede volver a ejecutar sin perder datos.

-- =========================================================
-- 1. Apoderados
-- =========================================================
create table if not exists public.apoderados (
  id               bigint generated always as identity primary key,
  nombre_apoderado text not null check (char_length(trim(nombre_apoderado)) between 3 and 120),
  nombre_hijo      text not null check (char_length(trim(nombre_hijo)) between 2 and 120),
  telefono         text not null check (telefono ~ '^\+?[0-9]{8,15}$'),
  correo           text check (correo is null or correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  creado_en        timestamptz not null default now()
);

alter table public.apoderados
  add column if not exists aporte_dinero     boolean not null default false,
  add column if not exists aporte_materiales boolean not null default false;

-- Columnas de la versión anterior (alimento / material con texto libre).
-- Si no tienen datos que quieras conservar, puedes borrarlas quitando los "--":
-- alter table public.apoderados drop column if exists dona_alimento, drop column if exists detalle_alimento,
--   drop column if exists dona_material, drop column if exists detalle_material;

-- =========================================================
-- 2. Lista de materiales y lo que cada familia compromete
-- =========================================================
create table if not exists public.materiales (
  id       bigint generated always as identity primary key,
  nombre   text not null unique,
  cantidad integer check (cantidad is null or cantidad > 0),  -- null = sin límite
  unidad   text,                                              -- ej: 'pliegos'
  orden    integer not null default 0,
  activo   boolean not null default true
);

create table if not exists public.aportes_materiales (
  id           bigint generated always as identity primary key,
  apoderado_id bigint not null references public.apoderados(id) on delete cascade,
  material_id  bigint not null references public.materiales(id),
  cantidad     integer check (cantidad is null or cantidad > 0),
  creado_en    timestamptz not null default now()
);

-- Lista del mural (solo se carga si la tabla está vacía)
insert into public.materiales (nombre, cantidad, unidad, orden)
select * from (values
  ('Goma eva café',                  7,    'pliegos', 1),
  ('Goma eva negra',                 3,    'pliegos', 2),
  ('Goma eva amarilla',              1,    'pliego',  3),
  ('Cartulina doble faz verde',      10,   null,      4),
  ('Cartulina beige',                6,    null,      5),
  ('Cartulina azul rey',             5,    null,      6),
  ('Cartulina roja',                 2,    null,      7),
  ('Cartulina amarilla',             2,    null,      8),
  ('Cartulina blanca',               2,    null,      9),
  ('Cartulina negra',                2,    null,      10),
  ('Papel crepé café',               10,   'pliegos', 11),
  ('Plato de cartón redondo grande', 1,    null,      12),
  ('Barras de silicona',             null, null,      13),
  ('Botellas plásticas de bebida',   null, null,      14)
) as v(nombre, cantidad, unidad, orden)
where not exists (select 1 from public.materiales);

-- =========================================================
-- 3. Seguridad: el público no toca las tablas directamente
-- =========================================================
alter table public.apoderados         enable row level security;
alter table public.materiales         enable row level security;
alter table public.aportes_materiales enable row level security;

drop policy if exists "publico_puede_insertar" on public.apoderados;
revoke all on public.apoderados, public.materiales, public.aportes_materiales from anon, authenticated;

-- =========================================================
-- 4. Funciones que usa el formulario
-- =========================================================

-- Materiales que todavía faltan
create or replace function public.materiales_disponibles()
returns table (id bigint, nombre text, unidad text, cantidad integer, restante integer)
language sql stable security definer set search_path = public as $$
  select m.id, m.nombre, m.unidad, m.cantidad,
         case when m.cantidad is null then null
              else m.cantidad - coalesce(sum(a.cantidad), 0)::int end as restante
  from materiales m
  left join aportes_materiales a on a.material_id = m.id
  where m.activo
  group by m.id
  having m.cantidad is null or m.cantidad - coalesce(sum(a.cantidad), 0) > 0
  order by m.orden, m.nombre;
$$;

-- Guarda la ficha y descuenta los materiales en una sola operación.
-- Si otra familia tomó el material justo antes, falla con 'MATERIAL_AGOTADO:<nombre>' y no guarda nada.
create or replace function public.registrar_apoderado(
  p_nombre_apoderado  text,
  p_nombre_hijo       text,
  p_telefono          text,
  p_correo            text,
  p_aporte_dinero     boolean,
  p_aporte_materiales boolean,
  p_materiales        jsonb default '[]'::jsonb   -- [{"id": 1, "cantidad": 2}, ...]
) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_id       bigint;
  v_item     jsonb;
  v_mat      materiales%rowtype;
  v_cant     integer;
  v_restante integer;
begin
  if coalesce(jsonb_array_length(p_materiales), 0) > 30 then
    raise exception 'DEMASIADOS_MATERIALES';
  end if;
  if p_aporte_materiales and coalesce(jsonb_array_length(p_materiales), 0) = 0 then
    raise exception 'FALTA_ELEGIR_MATERIALES';
  end if;

  insert into apoderados (nombre_apoderado, nombre_hijo, telefono, correo, aporte_dinero, aporte_materiales)
  values (trim(p_nombre_apoderado), trim(p_nombre_hijo), p_telefono, nullif(trim(p_correo), ''),
          coalesce(p_aporte_dinero, false), coalesce(p_aporte_materiales, false))
  returning id into v_id;

  if p_aporte_materiales then
    for v_item in select * from jsonb_array_elements(p_materiales) loop
      select * into v_mat from materiales
       where id = (v_item->>'id')::bigint and activo
       for update;
      if not found then raise exception 'MATERIAL_NO_EXISTE'; end if;

      if v_mat.cantidad is null then
        v_cant := null;
      else
        v_cant := coalesce((v_item->>'cantidad')::int, 1);
        select v_mat.cantidad - coalesce(sum(cantidad), 0) into v_restante
          from aportes_materiales where material_id = v_mat.id;
        if v_cant < 1 or v_cant > v_restante then
          raise exception 'MATERIAL_AGOTADO:%', v_mat.nombre;
        end if;
      end if;

      insert into aportes_materiales (apoderado_id, material_id, cantidad)
      values (v_id, v_mat.id, v_cant);
    end loop;
  end if;

  return v_id;
end;
$$;

revoke all on function public.materiales_disponibles() from public;
revoke all on function public.registrar_apoderado(text, text, text, text, boolean, boolean, jsonb) from public;
grant execute on function public.materiales_disponibles() to anon;
grant execute on function public.registrar_apoderado(text, text, text, text, boolean, boolean, jsonb) to anon;

-- =========================================================
-- 5. Vista para el jardín: quién trae qué (solo visible en el panel de Supabase)
-- =========================================================
create or replace view public.quien_trae_que as
select m.nombre as material,
       a.cantidad,
       ap.nombre_apoderado,
       ap.nombre_hijo,
       ap.telefono,
       a.creado_en
from aportes_materiales a
join materiales m  on m.id = a.material_id
join apoderados ap on ap.id = a.apoderado_id
order by m.orden, a.creado_en;

revoke all on public.quien_trae_que from anon, authenticated;
