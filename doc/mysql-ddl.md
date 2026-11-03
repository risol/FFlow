# MySQL DDL subset and ER rendering

`parseMysqlDdl` reads MySQL `CREATE TABLE` statements into the shared ER model.
Use `renderMysqlDdl` for the isolated Windows worker, or select
`FlowFileFormat.mysqlDdl` for file input:

```dart
final image = await renderer.renderMysqlDdl(sql,
    defaultSchema: 'shop', groupBySchema: true);
final file = await files.render(inputPath: 'schema.sql',
    format: FlowFileFormat.mysqlDdl, defaultSchema: 'shop');
```

The parser supports `USE`, `CREATE TABLE [IF NOT EXISTS]`, qualified names,
backtick identifiers, ordinary SQL comments and MySQL `#` comments, common
built-in column types and type parameters, nullability, defaults,
`AUTO_INCREMENT`, column comments, character sets and collations, `ON UPDATE`,
primary keys, unique keys, ordinary indexes, composite foreign keys and
`ON DELETE` / `ON UPDATE` actions. Common table options are retained in the
ER metadata: engine, charset, collation, comment, auto increment and row format.
Values and defaults are parsed as text and are never executed.

Unqualified table names use the current `USE` database, `defaultSchema`, or an
empty schema if neither is provided. A `USE` statement changes the current
database for subsequent names. Table and database names are matched exactly;
column references are matched case-insensitively. This is deterministic and does
not attempt to infer a server's `lower_case_table_names` setting.

This is a subset parser, not a MySQL server or schema validator. The syntax
assumes MySQL's default string quoting and backslash escape rules; modes such
as `ANSI_QUOTES` and `NO_BACKSLASH_ESCAPES` are not supported. `ALTER TABLE`,
`CREATE DATABASE`, `CREATE TABLE ... LIKE/AS`, generated columns, CHECK
constraints, full-text/spatial/functional or prefix indexes, and executable
version comments are rejected. Only foreign keys referencing a complete primary
or unique key are accepted; MySQL's non-unique referenced-index extension is
not supported. Include all referenced table definitions. Declared relationships
are shown without checking whether the selected storage engine enforces them.
Full database dumps may contain unsupported setup statements and need to be
reduced to supported `USE` and `CREATE TABLE` statements first.

Input is limited to 2 MB, 5,000 tables and 300 columns per table. Unsupported
or malformed input raises `MysqlDdlException` (a `FormatException`); isolated
rendering reports `PARSE_ERROR`.
