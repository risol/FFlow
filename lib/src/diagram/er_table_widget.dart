import 'package:flutter/material.dart';

/// ER table node for a `diagramToFlow` snapshot or another FFlow node builder.
///
/// Each entry in [columns] may contain `name`, `type`, `nullable`,
/// `primaryKey`, `foreignKey`, and `unique` fields, as produced by
/// `ErSchema.toDiagram`. This widget paints within its parent's dimensions.
class ErTableWidget extends StatelessWidget {
  const ErTableWidget(
      {super.key,
      required this.label,
      required this.columns,
      required this.background,
      required this.foreground,
      required this.border});

  final String label;
  final List<dynamic> columns;
  final Color background, foreground, border;

  @override
  Widget build(BuildContext context) {
    final dark = background.computeLuminance() < 0.4;
    Widget tag(String text, Color color) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(text,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Column(children: [
          Container(
              height: 46,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border))),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.bold))),
          for (final entry in columns)
            if (entry is Map)
              SizedBox(
                  height: 26,
                  child: Row(children: [
                    SizedBox(
                        width: 76,
                        child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Row(children: [
                              if (entry['primaryKey'] == true)
                                tag(
                                    'PK',
                                    dark
                                        ? const Color(0xffffd166)
                                        : const Color(0xff795000)),
                              if (entry['foreignKey'] == true)
                                tag(
                                    'FK',
                                    dark
                                        ? const Color(0xff91c7ff)
                                        : const Color(0xff205b95)),
                              if (entry['unique'] == true)
                                tag(
                                    'UQ',
                                    dark
                                        ? const Color(0xffd4b4ff)
                                        : const Color(0xff663399)),
                            ]))),
                    Expanded(
                        flex: 5,
                        child: Text('${entry['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: foreground, fontSize: 12))),
                    Expanded(
                        flex: 5,
                        child: Padding(
                            padding: const EdgeInsets.only(left: 6, right: 8),
                            child: Text(
                                '${entry['type'] ?? ''}${entry['nullable'] == false ? ' NOT NULL' : ''}',
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: foreground, fontSize: 11)))),
                  ])),
        ]),
      ),
    );
  }
}

/// Container node for a schema group produced by `ErSchema.toDiagram`.
class ErSchemaWidget extends StatelessWidget {
  const ErSchemaWidget(
      {super.key,
      required this.label,
      required this.foreground,
      required this.border});

  final String label;
  final Color foreground, border;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: foreground, fontWeight: FontWeight.bold)),
          ),
        ),
      );
}
