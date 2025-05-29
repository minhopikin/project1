-- List declarative partitions that are empty (row count = 0)
WITH partitions AS (
  SELECT 
    parent.relname AS parent_table,
    parent_ns.nspname AS parent_schema,
    child.relname AS partition_name,
    child_ns.nspname AS partition_schema,
    format('%I.%I', child_ns.nspname, child.relname) AS partition_full_name
  FROM pg_partitioned_table p
  JOIN pg_class parent ON p.partrelid = parent.oid
  JOIN pg_namespace parent_ns ON parent.relnamespace = parent_ns.oid
  JOIN pg_inherits i ON parent.oid = i.inhparent
  JOIN pg_class child ON i.inhrelid = child.oid
  JOIN pg_namespace child_ns ON child.relnamespace = child_ns.oid
),
partition_row_counts AS (
  SELECT 
    p.*,
    pg_stat.reltuples::BIGINT AS estimated_rows
  FROM partitions p
  JOIN pg_class pg_stat ON pg_stat.relname = p.partition_name
                        AND pg_stat.relnamespace = (
                          SELECT oid FROM pg_namespace WHERE nspname = p.partition_schema
                        )
)
SELECT *
FROM partition_row_counts
WHERE estimated_rows = 0
ORDER BY parent_schema, parent_table, partition_name;
