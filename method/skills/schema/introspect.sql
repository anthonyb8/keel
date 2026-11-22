-- Read a slice of a Postgres schema's structure, never its rows, as the JSON canvas.html draws.
--
--   psql "$DB_URL" -X -q -A -t -v schemas=public -v tables=orders,customers -f introspect.sql > schema.json
--
-- schemas: comma-separated schemas to look in.
-- tables:  comma-separated tables (name or schema.name) to focus on; empty for every table in schemas.
-- Tables one foreign key away from the focus come back as neighbours (focus: false), in any schema.
\set ON_ERROR_STOP on
with
params as (
  select string_to_array(:'schemas', ',') as schemas,
         string_to_array(nullif(:'tables', ''), ',') as tables
),
rels as (
  select c.oid, n.nspname as schema, c.relname as name, c.relkind, c.relrowsecurity as rls,
         obj_description(c.oid, 'pg_class') as comment
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p', 'v', 'm', 'f') and not c.relispartition
),
focus as (
  select r.oid from rels r, params p
  where r.schema = any(p.schemas)
    and (p.tables is null or r.name = any(p.tables) or r.schema || '.' || r.name = any(p.tables))
),
fks as (
  select con.conrelid, con.confrelid, k.attnum, k.fattnum, con.confdeltype
  from pg_constraint con
  cross join lateral unnest(con.conkey, con.confkey) as k(attnum, fattnum)
  where con.contype = 'f'
),
shown as (
  select oid, true as focus from focus
  union
  select f.oid, false from (
    select confrelid as oid from fks where conrelid in (select oid from focus)
    union
    select conrelid from fks where confrelid in (select oid from focus)
  ) f where f.oid not in (select oid from focus)
),
cols as (
  select a.attrelid, a.attnum, a.attname as name,
         format_type(a.atttypid, a.atttypmod) as type,
         not a.attnotnull as nullable,
         pg_get_expr(d.adbin, d.adrelid) as "default",
         a.attidentity <> '' as identity,
         a.attgenerated <> '' as generated,
         col_description(a.attrelid, a.attnum) as comment,
         case when t.typtype = 'e' then tn.nspname || '.' || t.typname end as enum,
         exists (select 1 from pg_index i where i.indrelid = a.attrelid and i.indisprimary
                 and a.attnum = any(i.indkey)) as pk,
         exists (select 1 from pg_index i where i.indrelid = a.attrelid and i.indisunique
                 and not i.indisprimary and i.indnatts = 1 and i.indkey[0] = a.attnum) as "unique"
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  join pg_namespace tn on tn.oid = t.typnamespace
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid in (select oid from shown) and a.attnum > 0 and not a.attisdropped
),
refs as (
  select f.conrelid, f.attnum,
         json_agg(json_build_object(
           'table', r.schema || '.' || r.name,
           'column', fa.attname,
           'onDelete', case f.confdeltype when 'c' then 'cascade' when 'n' then 'set null'
                         when 'd' then 'set default' when 'r' then 'restrict' else 'no action' end
         )) as fk
  from fks f
  join rels r on r.oid = f.confrelid
  join pg_attribute fa on fa.attrelid = f.confrelid and fa.attnum = f.fattnum
  where f.conrelid in (select oid from shown)
  group by f.conrelid, f.attnum
),
tables as (
  select json_build_object(
    'id', r.schema || '.' || r.name,
    'schema', r.schema,
    'name', r.name,
    'kind', case r.relkind when 'v' then 'view' when 'm' then 'materialized view'
              when 'f' then 'foreign table' else 'table' end,
    'focus', s.focus,
    'rls', r.rls,
    'policies', coalesce((select json_agg(json_build_object('name', p.policyname, 'cmd', p.cmd) order by p.policyname)
                          from pg_policies p where p.schemaname = r.schema and p.tablename = r.name), '[]'::json),
    'comment', r.comment,
    'columns', coalesce((select json_agg(json_strip_nulls(json_build_object(
                 'name', c.name, 'type', c.type, 'nullable', c.nullable, 'default', c."default",
                 'pk', c.pk, 'unique', c."unique", 'identity', c.identity, 'generated', c.generated,
                 'comment', c.comment, 'enum', c.enum, 'fk', rf.fk)) order by c.attnum)
               from cols c left join refs rf on rf.conrelid = c.attrelid and rf.attnum = c.attnum
               where c.attrelid = r.oid), '[]'::json)
  ) as t, s.focus, r.schema, r.name
  from shown s join rels r on r.oid = s.oid
),
enums as (
  select json_build_object(
    'id', n.nspname || '.' || t.typname, 'schema', n.nspname, 'name', t.typname,
    'values', (select json_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid)
  ) as e, n.nspname, t.typname
  from pg_type t join pg_namespace n on n.oid = t.typnamespace
  where t.typtype = 'e' and n.nspname || '.' || t.typname in (select enum from cols where enum is not null)
)
select json_build_object(
  'database', current_database(),
  'tables', coalesce((select json_agg(t order by not focus, schema, name) from tables), '[]'::json),
  'enums', coalesce((select json_agg(e order by nspname, typname) from enums), '[]'::json)
);
