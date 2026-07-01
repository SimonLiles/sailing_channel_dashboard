/* ====================================================================
   Layer: 00_Utils
   Purpose: Clones an entire BigQuery dataset (tables, views, routines)
            into a new target project.dataset.
   Dialect: Google BigQuery Standard SQL
   Requirements:
      - The target dataset must already exist in BigQuery (create it first
        in the desired location before calling this procedure).
   Usage:
      -- Zero-copy clone (tables only):
      CALL `{{project}}.{{dataset}}.clone_dataset`(
        'source_project', 'source_dataset',
        'target_project', 'target_dataset',
        FALSE, FALSE, FALSE
      );

      -- Full copy including views and routines:
      CALL `{{project}}.{{dataset}}.clone_dataset`(
        'source_project', 'source_dataset',
        'target_project', 'target_dataset',
        TRUE, TRUE, TRUE
      );
   Notes:
      - All 7 params are positional (BigQuery does not support DEFAULT).
      - Tables use CLONE (zero-copy) when full_copy = FALSE,
        or COPY (full data copy) when full_copy = TRUE.
      - Views and routines are recreated from their DDL definitions.
      - Does NOT copy dataset-level ACLs, labels, tags, or the dataset
        itself (create the target dataset beforehand).
 ==================================================================== */

CREATE OR REPLACE PROCEDURE `{{project}}.{{dataset}}.clone_dataset`(
    source_project    STRING,
    source_dataset    STRING,
    target_project    STRING,
    target_dataset    STRING,
    include_views     BOOLEAN,
    include_routines  BOOLEAN,
    full_copy         BOOLEAN
)
BEGIN
    DECLARE ddl        STRING;
    DECLARE i          INT64 DEFAULT 0;
    DECLARE tbl_names  ARRAY<STRING>;
    DECLARE vw_names   ARRAY<STRUCT<name STRING, definition STRING>>;
    DECLARE rt_names   ARRAY<STRUCT<name STRING, type STRING, ddl STRING>>;

    -- ------------------------------------------------------------------
    -- 1. Clone / Copy all BASE TABLES
    -- ------------------------------------------------------------------
    EXECUTE IMMEDIATE FORMAT("""
        SELECT ARRAY_AGG(table_name ORDER BY table_name)
        FROM `%s.%s.INFORMATION_SCHEMA.TABLES`
        WHERE table_type = 'BASE TABLE'
    """, source_project, source_dataset)
    INTO tbl_names;

    SET i = 0;
    WHILE i < ARRAY_LENGTH(tbl_names) DO
        IF full_copy THEN
            SET ddl = FORMAT("""
                CREATE OR REPLACE TABLE `%s.%s.%s`
                COPY `%s.%s.%s`
            """,
                target_project, target_dataset, tbl_names[i],
                source_project, source_dataset, tbl_names[i]
            );
        ELSE
            SET ddl = FORMAT("""
                CREATE OR REPLACE TABLE `%s.%s.%s`
                CLONE `%s.%s.%s`
            """,
                target_project, target_dataset, tbl_names[i],
                source_project, source_dataset, tbl_names[i]
            );
        END IF;

        EXECUTE IMMEDIATE ddl;
        SET i = i + 1;
    END WHILE;

    -- ------------------------------------------------------------------
    -- 4. (Optional) Recreate all VIEWS
    -- ------------------------------------------------------------------
    IF include_views THEN
        EXECUTE IMMEDIATE FORMAT("""
            SELECT ARRAY_AGG(
                       STRUCT(table_name AS name, view_definition AS definition)
                       ORDER BY table_name
                   )
            FROM `%s.%s.INFORMATION_SCHEMA.VIEWS`
        """, source_project, source_dataset)
        INTO vw_names;

        SET i = 0;
        WHILE i < ARRAY_LENGTH(vw_names) DO
            SET ddl = FORMAT("""
                CREATE OR REPLACE VIEW `%s.%s.%s`
                AS %s
            """,
                target_project, target_dataset, vw_names[i].name,
                vw_names[i].definition
            );

            EXECUTE IMMEDIATE ddl;
            SET i = i + 1;
        END WHILE;
    END IF;

    -- ------------------------------------------------------------------
    -- 5. (Optional) Recreate all ROUTINES (functions & procedures)
    -- ------------------------------------------------------------------
    IF include_routines THEN
        EXECUTE IMMEDIATE FORMAT("""
            SELECT ARRAY_AGG(
                       STRUCT(routine_name AS name,
                              routine_type AS type,
                              ddl          AS ddl)
                       ORDER BY routine_name
                   )
            FROM `%s.%s.INFORMATION_SCHEMA.ROUTINES`
            WHERE routine_type IN ('PROCEDURE', 'FUNCTION')
        """, source_project, source_dataset)
        INTO rt_names;

        SET i = 0;
        WHILE i < ARRAY_LENGTH(rt_names) DO
            -- Rewrite the original project.dataset references to target
            SET ddl = REGEXP_REPLACE(
                rt_names[i].ddl,
                CONCAT(r'`', source_project, r'\.', source_dataset, r'\.'),
                CONCAT('`', target_project, '.', target_dataset, '.')
            );

            EXECUTE IMMEDIATE ddl;
            SET i = i + 1;
        END WHILE;
    END IF;

END;
