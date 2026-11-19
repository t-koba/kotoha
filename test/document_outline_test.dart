import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/document_blocks.dart';
import 'package:kotoha/main.dart';

const _source = '''
## Heading
First paragraph
continues here

- alpha
- beta

```
code line
```

```
```

Last line''';

List<String> _labels(Locale locale) => [
  'Heading',
  'First paragraph continues here',
  'alpha',
  'beta',
  'code line',
  locale.languageCode == 'ja' ? '（空のブロック）' : '(empty block)',
  'Last line',
];

void _platformTest(
  String description,
  TargetPlatform platform,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<TextEditingController> _pumpApp(
  WidgetTester tester, {
  required Locale locale,
  String source = '',
}) async {
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const KotohaApp());
  await tester.pumpAndSettle();
  final field = find.byKey(const ValueKey('source-text'));
  if (source.isNotEmpty) await tester.enterText(field, source);
  await tester.pumpAndSettle();
  return tester.widget<TextField>(field).controller!;
}

bool _focusesSource(WidgetTester tester) {
  final editable = find.descendant(
    of: find.byKey(const ValueKey('source-text')),
    matching: find.byType(EditableText),
  );
  return identical(
    tester.binding.focusManager.primaryFocus,
    tester.widget<EditableText>(editable).focusNode,
  );
}

void main() {
  final platforms = <(TargetPlatform, Locale, String)>[
    (TargetPlatform.macOS, const Locale('en'), 'Document outline'),
    (TargetPlatform.android, const Locale('ja'), '原文の構成'),
    (TargetPlatform.iOS, const Locale('en'), 'Document outline'),
  ];

  for (final (platform, locale, title) in platforms) {
    _platformTest(
      'outline entries match parsed source on $platform',
      platform,
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final controller = await _pumpApp(
            tester,
            locale: locale,
            source: _source,
          );
          final blocks = parseDocumentBlocks(_source);
          expect(
            find.byKey(const ValueKey('document-outline')),
            findsOneWidget,
          );
          expect(find.text(title), findsOneWidget);
          final labels = _labels(locale);
          expect(blocks, hasLength(labels.length));

          for (var index = 0; index < blocks.length; index++) {
            final finder = find.byKey(ValueKey('document-block-$index'));
            expect(finder, findsOneWidget, reason: 'block $index');
            expect(
              (tester.widget<ListTile>(finder).title! as Text).data,
              labels[index],
              reason: 'block $index',
            );
            expect(
              find.bySemanticsIdentifier('document-block-$index'),
              findsOneWidget,
              reason: 'block $index semantics identifier',
            );
          }
          expect(find.byKey(const ValueKey('document-block-7')), findsNothing);
          expect(controller.text, _source);
        } finally {
          semantics.dispose();
        }
      },
    );

    _platformTest(
      'tapping an entry selects its source range on $platform',
      platform,
      (tester) async {
        final source = '## 見出し 😀\n最初の段落\n続き\n\n- item\n\nTail';
        final controller = await _pumpApp(
          tester,
          locale: locale,
          source: source,
        );
        final blocks = parseDocumentBlocks(source);
        expect(blocks, hasLength(4));

        for (var index = 0; index < blocks.length; index++) {
          final entry = find.byKey(ValueKey('document-block-$index'));
          await tester.ensureVisible(entry);
          await tester.pumpAndSettle();
          await tester.tap(entry);
          await tester.pumpAndSettle();

          expect(
            controller.selection,
            TextSelection(
              baseOffset: blocks[index].start,
              extentOffset: blocks[index].end,
            ),
            reason: 'block $index selection',
          );
          expect(controller.text, source, reason: 'block $index text');
          expect(_focusesSource(tester), isTrue, reason: 'block $index focus');
        }
      },
    );

    _platformTest(
      'editing the source updates the outline on $platform',
      platform,
      (tester) async {
        await _pumpApp(tester, locale: locale, source: '## Before\nOld body');
        expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
        expect(find.text('Before'), findsOneWidget);
        expect(find.text('Old body'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('source-text')),
          '## After\nNew body\n\n- item',
        );
        await tester.pumpAndSettle();

        expect(find.text('After'), findsOneWidget);
        expect(find.text('New body'), findsOneWidget);
        expect(find.text('item'), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-2')), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-3')), findsNothing);
        expect(find.text('Before'), findsNothing);
        expect(find.text('Old body'), findsNothing);
      },
    );

    _platformTest(
      'outline entries are reachable by keyboard on $platform',
      platform,
      (tester) async {
        const keyboardSource = '## One\nBody one\n\n## Two\nBody two';
        await _pumpApp(tester, locale: locale, source: keyboardSource);
        final blocks = parseDocumentBlocks(keyboardSource);
        expect(blocks, hasLength(4));

        final reached = <String>{};
        for (var tab = 0; tab < 40 && reached.length < blocks.length; tab++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final key = tester.binding.focusManager.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<ListTile>()
              ?.key;
          if (key is ValueKey<String> &&
              key.value.startsWith('document-block-')) {
            reached.add(key.value);
          }
        }
        expect(
          reached,
          containsAll(<String>[
            for (var index = 0; index < blocks.length; index++)
              'document-block-$index',
          ]),
        );

        final index = int.parse(reached.last.split('-').last);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final controller = tester
            .widget<TextField>(find.byKey(const ValueKey('source-text')))
            .controller!;
        expect(
          controller.selection,
          TextSelection(
            baseOffset: blocks[index].start,
            extentOffset: blocks[index].end,
          ),
        );
        expect(_focusesSource(tester), isTrue);
      },
    );
  }

  for (final (locale, title, empty) in [
    (
      const Locale('en'),
      'Document outline',
      'No blocks in the source text yet.',
    ),
    (const Locale('ja'), '原文の構成', '原文にはまだブロックがありません。'),
  ]) {
    _platformTest(
      'empty source shows the localized outline state for $locale',
      TargetPlatform.macOS,
      (tester) async {
        await _pumpApp(tester, locale: locale);
        expect(find.text(title), findsOneWidget);
        expect(find.text(empty), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-0')), findsNothing);

        await tester.enterText(
          find.byKey(const ValueKey('source-text')),
          '  \n\t\n',
        );
        await tester.pumpAndSettle();
        expect(find.text(empty), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-0')), findsNothing);
      },
    );
  }
}
