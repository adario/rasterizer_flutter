import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:widgetbook/widgetbook.dart';

/// The app around each use case, with a bar above it, as in Flame's
/// examples.
///
/// The bar shows the use case's name, and buttons for its description and
/// its code.
class const ExampleApp({required final Widget child, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final useCase = WidgetbookState.of(context).useCase;
    return MaterialApp(
      title: 'Flame Rasterizer',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      home: Material(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (useCase is ExampleUseCase) _ExampleBar(useCase),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// The bar above a use case: its name, and buttons for its description and
/// its code.
class const _ExampleBar(final ExampleUseCase useCase) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              useCase.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Description',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              useRootNavigator: false,
              builder: (_) => _InfoDialog(useCase),
            ),
          ),
          IconButton(
            tooltip: 'See code',
            icon: const Icon(Icons.code),
            onPressed: () => launchUrl(Uri.parse(useCase.codeLink)),
          ),
        ],
      ),
    );
  }
}

/// A dialog with a use case's description.
class const _InfoDialog(final ExampleUseCase useCase) extends StatelessWidget {
  static final _paragraphBreak = RegExp(r'\n{2,}');

  /// A line break within a paragraph: one that doesn't start a list item.
  static final _lineBreak = RegExp(r'\n(?!\d+\. |[-*] )');

  /// The description, with the lines of each paragraph joined so that the
  /// text wraps freely.
  ///
  /// The descriptions are written like Markdown, with blank lines between
  /// paragraphs and line breaks by hand. List items stay on their own lines.
  String get _description {
    return useCase.info
        .split('\n')
        .map((line) => line.trim())
        .join('\n')
        .trim()
        .split(_paragraphBreak)
        .map((paragraph) => paragraph.replaceAll(_lineBreak, ' '))
        .join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(useCase.name),
      content: SelectableText(_description),
      scrollable: true,
      constraints: const BoxConstraints(maxWidth: 600),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
