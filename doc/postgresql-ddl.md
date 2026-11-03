# PostgreSQL DDL subset and ER rendering

`parsePostgresDdl` reads SQL as text; it never connects to a database or
executes statements. It returns an immutable `ErSchema`, and `toDiagram()`
converts it to the shared `DiagramDocument`. The desktop service offers the
combined `renderPostgresDdl` API:

```dart
final schema = parsePostgresDdl(sqlText);
final diagram = schema.toDiagram(title: '订单结构');
final image = await renderer.renderPostgresDdl(sqlText, title: '订单结构');
```

Supported input is a sequence of `CREATE TABLE` statements with optional
`IF NOT EXISTS`, schema-qualified or quoted names, standard quoted string
literals, line comments and nested block comments. Unquoted identifiers are
folded to lowercase; an unqualified table uses `public`. Columns support
single-word or schema-qualified types, common multiword PostgreSQL types,
numeric type modifiers and `[]` array suffixes. Inline and named/table-level
primary keys, unique constraints and foreign keys are retained, including
composite column mappings, `NOT NULL`, `NULL`, defaults, and `ON DELETE` /
`ON UPDATE` actions (`NO ACTION`, `RESTRICT`, `CASCADE`, `SET NULL`,
`SET DEFAULT`). A `REFERENCES` clause without columns resolves to the target
primary key. Every referenced table must appear in the supplied input and the
referenced columns must form a declared primary or unique key.

Defaults support literals, function calls, arrays, casts, parentheses,
arithmetic, concatenation and unary `NOT`; their source text is preserved.
They are not evaluated or type-checked. This reader is not a replacement for
PostgreSQL's own syntax and semantic validation. `ALTER TABLE`, indexes, `CHECK`, generated
columns, collations, table inheritance, `MATCH`, deferrability, dollar-quoted
strings, escape strings, multiple dialects and other DDL are not supported;
unsupported constructs are rejected when recognized. Some complex type and
default-expression forms are outside this subset. Errors carry line, column
and UTF-16 offset in `PostgresDdlException`. Input is capped at 2 MB, 5,000
tables and 300 columns per table.

The worker draws one table per node, including the ordered fields, types,
`NOT NULL`, and distinguishable PK, FK and single-column UQ tags. Composite
unique and foreign keys are preserved in the diagram data; the displayed
relationship label may be truncated to avoid covering the markers. Crow's foot
markers show zero-or-many on the referencing side, or zero-or-one when its
foreign-key columns cover a declared unique key; the referenced side is one
or zero-or-one according to FK nullability. Self-references route around the
table. Large diagrams may exceed the configured pixel limit, and complicated
relationship networks can still have crossed edges or overlapping labels.

To group tables into outlined schema containers, pass `groupBySchema: true`
to `renderPostgresDdl`, to `FlowFileRenderService.render` for a PostgreSQL DDL
file, or to `ErSchema.toDiagram`. Grouping preserves foreign keys between
schemas and uses the same layered layout. Large groups still count toward the
graph and image limits; complex relationships may cross group boundaries.
