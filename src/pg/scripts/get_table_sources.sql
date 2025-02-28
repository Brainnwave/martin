WITH columns AS (
  SELECT
    ns.nspname AS table_schema,
    class.relname AS table_name,
    attr.attname AS column_name,
    trim(leading '_' from tp.typname) AS type_name
  FROM pg_attribute attr
    JOIN pg_catalog.pg_class AS class ON class.oid = attr.attrelid
    JOIN pg_catalog.pg_namespace AS ns ON ns.oid = class.relnamespace
    JOIN pg_catalog.pg_type AS tp ON tp.oid = attr.atttypid
  WHERE NOT attr.attisdropped AND attr.attnum > 0),
spatially_indexed_columns AS (
  SELECT ns.nspname AS table_schema,
    class.relname AS table_name,
    attr.attname AS column_name
  FROM pg_attribute attr
  JOIN pg_class class on class.oid = attr.attrelid
  JOIN pg_namespace ns on ns.oid = class.relnamespace
  JOIN pg_index ix on
    ix.indrelid = class.oid and
    ix.indnkeyatts = 1 and -- consider single column indices only
    attr.attnum = ix.indkey[0]
  JOIN pg_opclass op ON
    op.oid = ix.indclass[0] AND
    op.opcname IN ('gist_geometry_ops_2d', 'spgist_geometry_ops_2d', 'brin_geometry_inclusion_ops_2d')
  GROUP BY 1, 2, 3),
annotated_geometry_columns AS (
  SELECT
    f_table_schema AS schema, f_table_name AS name, f_geometry_column AS geom, srid, type,
      COALESCE(class.relkind = 'v', false) AS is_view,
      bool_or(sic.column_name is not null) as geom_idx
  FROM geometry_columns
  JOIN pg_catalog.pg_class AS class ON class.relname = geometry_columns.f_table_name
  JOIN pg_catalog.pg_namespace AS ns ON ns.nspname = geometry_columns.f_table_schema
  LEFT JOIN spatially_indexed_columns AS sic ON
    geometry_columns.f_table_schema = sic.table_schema AND
    geometry_columns.f_table_name = sic.table_name AND
    geometry_columns.f_geometry_column = sic.column_name
  GROUP BY 1, 2, 3, 4, 5, 6)
SELECT
  schema, name, geom, srid, type, is_view, geom_idx,
    COALESCE(
      jsonb_object_agg(columns.column_name, columns.type_name) FILTER (WHERE columns.column_name IS NOT NULL AND columns.type_name != 'geometry'),
      '{}'::jsonb
    ) as properties
FROM annotated_geometry_columns AS gc
LEFT JOIN columns ON
  gc.schema = columns.table_schema AND
  gc.name = columns.table_name AND
  gc.geom != columns.column_name
GROUP BY gc.schema, gc.name, gc.geom, gc.srid, gc.type, gc.is_view, gc.geom_idx;
