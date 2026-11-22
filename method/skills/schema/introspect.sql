-- Read a slice of a Postgres schema's structure, never its rows, as the JSON canvas.html draws.
--
--   psql "$DB_URL" -X -q -A -t -v schemas=public -v tables=orders,customers -f introspect.sql > schema.json
--
-- schemas: comma-separated schemas to look in.
-- tables:  comma-separated tables (name or schema.name) to focus on; empty for every table in schemas.
-- Tables one foreign key away from the focus come back as neighbours (focus: false), in any schema.
\set ON_ERROR_STOP on
with recursive
params as (
  select regexp_split_to_array(btrim(:'schemas'), '\s*,\s*') as schemas,
         regexp_split_to_array(nullif(btrim(:'tables'), ''), '\s*,\s*') as tables
),
rels as (
  select c.oid, n.nspname as schema, c.relname as name, c.relkind, c.relrowsecurity as rls, c.relispartition,
         obj_description(c.oid, 'pg_class') as comment
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p', 'v', 'm', 'f')
),
focus as (
  select r.oid from rels r, params p
  where r.schema = any(p.schemas)
    and ((p.tables is null and not r.relispartition) or r.name = any(p.tables) or r.schema || '.' || r.name = any(p.tables))
),
-- Postgres copies a key onto each partition of either side. A copy on a partition of the referencing
-- table is that partition's own key; one that points at a partition of the referenced table is not drawn.
declared as (
  select oid, confrelid as target, false as inherited from pg_constraint where contype = 'f' and conparentid = 0
  union all
  select con.oid, d.target, true from pg_constraint con join declared d on con.conparentid = d.oid
),
fks as (
  select con.conrelid, con.confrelid, con.conkey, k.attnum, k.fattnum, con.confdeltype, d.inherited
  from pg_constraint con
  join declared d on d.oid = con.oid and d.target = con.confrelid
  cross join lateral unnest(con.conkey, con.confkey) as k(attnum, fattnum)
),
shown as (
  select oid, true as focus from focus
  union
  select f.oid, false from (
    select confrelid as oid from fks where conrelid in (select oid from focus)
    union
    select conrelid from fks where confrelid in (select oid from focus) and not inherited
  ) f where f.oid not in (select oid from focus)
),
-- The key columns of each index that makes every row unique: not a partial or expression index,
-- and without the columns an INCLUDE carries along.
uniques as (
  select i.indrelid, i.indisprimary, (i.indkey::int2[])[0:i.indnkeyatts - 1] as key
  from pg_index i
  where i.indisunique and i.indisvalid and i.indpred is null and i.indexprs is null
),
-- Each type with the one beneath it: a domain's base, an array's element, down to the plain type.
bases as (
  select oid, oid as base from pg_type
  union all
  select b.oid, case when t.typtype = 'd' then t.typbasetype else t.typelem end
  from bases b join pg_type t on t.oid = b.base
  where t.typtype = 'd' or (t.typcategory = 'A' and t.typelem <> 0)
),
enum_of as (
  select b.oid, n.nspname || '.' || t.typname as enum
  from bases b join pg_type t on t.oid = b.base join pg_namespace n on n.oid = t.typnamespace
  where t.typtype = 'e'
),
cols as (
  select a.attrelid, a.attnum, a.attname as name,
         format_type(a.atttypid, a.atttypmod) as type,
         not a.attnotnull as nullable,
         pg_get_expr(d.adbin, d.adrelid) as "default",
         a.attidentity <> '' as identity,
         a.attgenerated <> '' as generated,
         col_description(a.attrelid, a.attnum) as comment,
         eo.enum,
         exists (select 1 from uniques u where u.indrelid = a.attrelid and u.indisprimary
                 and a.attnum = any(u.key)) as pk,
         exists (select 1 from uniques u where u.indrelid = a.attrelid and not u.indisprimary
                 and u.key <@ array[a.attnum]) as "unique"
  from pg_attribute a
  left join enum_of eo on eo.oid = a.atttypid
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid in (select oid from shown) and a.attnum > 0 and not a.attisdropped
),
refs as (
  select f.conrelid, f.attnum,
         json_agg(json_build_object(
           'table', r.schema || '.' || r.name,
           'column', fa.attname,
           'one', exists (select 1 from uniques u where u.indrelid = f.conrelid and u.key <@ f.conkey),
           'optional', exists (select 1 from pg_attribute k where k.attrelid = f.conrelid
                               and k.attnum = any(f.conkey) and not k.attnotnull),
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
