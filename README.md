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
------------------
--script to generate drop table statements----
-- Generate DROP TABLE statements for empty declarative partitions
WITH partitions AS (
    SELECT 
        child_ns.nspname AS partition_schema,
        child.relname AS partition_name,
        format('%I.%I', child_ns.nspname, child.relname) AS full_partition_name
    FROM pg_partitioned_table p
    JOIN pg_class parent ON p.partrelid = parent.oid
    JOIN pg_inherits i ON parent.oid = i.inhparent
    JOIN pg_class child ON i.inhrelid = child.oid
    JOIN pg_namespace child_ns ON child.relnamespace = child_ns.oid
),
row_counts AS (
    SELECT 
        p.*,
        (SELECT COUNT(*) FROM pg_catalog.pg_class c 
         WHERE c.oid = (quote_ident(p.partition_schema) || '.' || quote_ident(p.partition_name))::regclass) AS sanity_check
    FROM partitions p
),
real_counts AS (
    SELECT 
        p.partition_schema,
        p.partition_name,
        p.full_partition_name,
        (SELECT COUNT(*) FROM pg_catalog.pg_class c 
         WHERE c.oid = (quote_ident(p.partition_schema) || '.' || quote_ident(p.partition_name))::regclass) AS estimated_rows,
        (SELECT COUNT(*) FROM (SELECT 1 FROM 
            format('%I.%I', p.partition_schema, p.partition_name)::regclass LIMIT 1) sub) AS exists_check,
        (SELECT COUNT(*) FROM format('%I.%I', p.partition_schema, p.partition_name)::regclass) AS exact_count
    FROM partitions p
)
SELECT 
    format('DROP TABLE %I.%I CASCADE;', partition_schema, partition_name) AS drop_statement
FROM real_counts
WHERE exact_count = 0;
---------------------

DO
$$
DECLARE
    part RECORD;
    row_count BIGINT;
BEGIN
    FOR part IN
        SELECT 
            child_ns.nspname AS partition_schema,
            child.relname AS partition_name,
            format('%I.%I', child_ns.nspname, child.relname) AS full_partition_name
        FROM pg_partitioned_table p
        JOIN pg_class parent ON p.partrelid = parent.oid
        JOIN pg_inherits i ON parent.oid = i.inhparent
        JOIN pg_class child ON i.inhrelid = child.oid
        JOIN pg_namespace child_ns ON child.relnamespace = child_ns.oid
    LOOP
        BEGIN
            EXECUTE format('SELECT COUNT(*) FROM %I.%I', part.partition_schema, part.partition_name) INTO row_count;
            IF row_count = 0 THEN
                RAISE NOTICE 'DROP TABLE %I.%I CASCADE;', part.partition_schema, part.partition_name;
            END IF;
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'Skipped % due to error.', part.full_partition_name;
        END;
    END LOOP;
END
$$ LANGUAGE plpgsql;


