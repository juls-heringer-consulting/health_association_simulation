/* =============================================================================
   103_data_dictionary.sql
   A data dictionary that is generated from the database itself (system catalog
   views + MS_Description extended properties), so it can never drift away from
   the real schema. python/export_data_dictionary.py turns it into Markdown.
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER VIEW meta.v_data_dictionary
AS
SELECT
    s.name                                   AS schema_name,
    t.name                                   AS table_name,
    CAST(tp.value AS NVARCHAR(4000))         AS table_description,
    c.column_id,
    c.name                                   AS column_name,
    CASE
        WHEN ty.name IN (N'varchar', N'char', N'varbinary', N'binary')
            THEN ty.name + N'(' + IIF(c.max_length = -1, N'MAX', CAST(c.max_length AS NVARCHAR(10))) + N')'
        WHEN ty.name IN (N'nvarchar', N'nchar')
            THEN ty.name + N'(' + IIF(c.max_length = -1, N'MAX', CAST(c.max_length / 2 AS NVARCHAR(10))) + N')'
        WHEN ty.name IN (N'decimal', N'numeric')
            THEN ty.name + N'(' + CAST(c.precision AS NVARCHAR(3)) + N',' + CAST(c.scale AS NVARCHAR(3)) + N')'
        WHEN ty.name IN (N'datetime2', N'time', N'datetimeoffset')
            THEN ty.name + N'(' + CAST(c.scale AS NVARCHAR(3)) + N')'
        ELSE ty.name
    END                                      AS data_type,
    c.is_nullable,
    c.is_identity,
    CAST(IIF(pk.column_id IS NULL, 0, 1) AS BIT) AS is_primary_key,
    fk.references_table,
    CAST(cp.value AS NVARCHAR(4000))         AS column_description
FROM sys.tables  AS t
JOIN sys.schemas AS s  ON s.schema_id = t.schema_id
JOIN sys.columns AS c  ON c.object_id = t.object_id
JOIN sys.types   AS ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.extended_properties AS tp
       ON tp.class = 1 AND tp.major_id = t.object_id AND tp.minor_id = 0 AND tp.name = N'MS_Description'
LEFT JOIN sys.extended_properties AS cp
       ON cp.class = 1 AND cp.major_id = t.object_id AND cp.minor_id = c.column_id AND cp.name = N'MS_Description'
OUTER APPLY (
    SELECT ic.column_id
    FROM sys.indexes AS i
    JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.object_id = t.object_id AND i.is_primary_key = 1 AND ic.column_id = c.column_id
) AS pk
OUTER APPLY (
    SELECT TOP (1) OBJECT_SCHEMA_NAME(fkc.referenced_object_id) + N'.' + OBJECT_NAME(fkc.referenced_object_id) AS references_table
    FROM sys.foreign_key_columns AS fkc
    WHERE fkc.parent_object_id = t.object_id AND fkc.parent_column_id = c.column_id
) AS fk
WHERE s.name IN (N'meta', N'stg', N'core', N'mart');
GO
