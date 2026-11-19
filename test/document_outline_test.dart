import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/document_blocks.dart';
import 'package:kotoha/document_outline.dart';
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

String _longSource(String firstHeading) =>
    '## $firstHeading\n${'## Repeated line\n' * (maxOutlineSourceLength ~/ 16)}';

const _truncatedNoticeEn =
    'The outline covers only the beginning of the source. The full text remains editable.';
const _entryCapEn =
    'Only the first 200 outline entries are shown. The full text remains editable.';
const _entryCapJa = '構成の項目は最初の200件のみ表示します。全文は引き続き編集できます。';

const _noMatchesEn = 'No outline entries match this search.';
const _noMatchesJa = '検索に一致する構成の項目はありません。';
const _matchCapEn = 'Only the first 200 matching outline entries are shown.';
const _matchCapJa = '一致する構成の項目は最初の200件のみ表示します。';

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

  for (final (locale, notice) in [
    (const Locale('en'), _truncatedNoticeEn),
    (const Locale('ja'), '構成は原文の先頭のみを表示します。全文は引き続き編集できます。'),
  ]) {
    _platformTest(
      'source past the outline prefix is disclosed and bounded for $locale',
      TargetPlatform.macOS,
      (tester) async {
        final source = _longSource('Beginning');
        expect(source.length, greaterThan(maxOutlineSourceLength));
        final controller = await _pumpApp(
          tester,
          locale: locale,
          source: source,
        );
        expect(find.text(notice), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
        expect(
          find.byKey(ValueKey('document-block-${maxVisibleOutlineBlocks - 1}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('document-block-$maxVisibleOutlineBlocks')),
          findsNothing,
        );

        final expected = parseDocumentBlocks(
          source.substring(0, maxOutlineSourceLength),
        ).first;
        final entry = find.byKey(const ValueKey('document-block-0'));
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(
          controller.selection,
          TextSelection(baseOffset: expected.start, extentOffset: expected.end),
        );
        expect(controller.text, source);
      },
    );
  }

  _platformTest(
    'a prefix with too many blocks is disclosed and bounded',
    TargetPlatform.macOS,
    (tester) async {
      final source = List<String>.generate(
        maxVisibleOutlineBlocks + 20,
        (index) => '## Heading $index',
      ).join('\n');
      expect(source.length, lessThan(maxOutlineSourceLength));
      await _pumpApp(tester, locale: const Locale('en'), source: source);
      expect(find.text(_truncatedNoticeEn), findsNothing);
      expect(find.text(_entryCapEn), findsOneWidget);
      expect(find.text(_matchCapEn), findsNothing);
      final last = find.byKey(
        ValueKey('document-block-${maxVisibleOutlineBlocks - 1}'),
      );
      expect(last, findsOneWidget);
      expect(
        (tester.widget<ListTile>(last).title! as Text).data,
        'Heading ${maxVisibleOutlineBlocks - 1}',
      );
      expect(
        find.byKey(ValueKey('document-block-$maxVisibleOutlineBlocks')),
        findsNothing,
      );
    },
  );

  _platformTest(
    'editing a large source refreshes the bounded prefix',
    TargetPlatform.macOS,
    (tester) async {
      await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: _longSource('BeforeEdit'),
      );
      expect(find.text('BeforeEdit'), findsOneWidget);

      final field = find.byKey(const ValueKey('source-text'));
      await tester.enterText(field, _longSource('AfterEdit'));
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text.startsWith('## AfterEdit'), isTrue);
      expect(controller.text.length, greaterThan(maxOutlineSourceLength));
      expect(find.text('BeforeEdit'), findsNothing);
      expect(find.text('AfterEdit'), findsOneWidget);
      expect(find.text(_truncatedNoticeEn), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
      expect(
        find.byKey(ValueKey('document-block-$maxVisibleOutlineBlocks')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _platformTest(
    'selection changes do not rebuild outline entries',
    TargetPlatform.macOS,
    (tester) async {
      const source = '## Heading\nBody';
      final controller = await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: source,
      );
      final entry = find.byKey(const ValueKey('document-block-0'));
      final before = tester.widget<ListTile>(entry).title! as Text;
      expect(before.data, 'Heading');

      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(
        tester.widget<ListTile>(entry).title! as Text,
        same(before),
        reason: 'a selection-only notification must not rebuild the outline',
      );

      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        '## Updated\nBody',
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Heading'), findsNothing);
      expect(
        tester.widget<ListTile>(entry).title! as Text,
        isNot(same(before)),
      );
      expect(controller.text, '## Updated\nBody');
    },
  );

  for (final (platform, locale, searchLabel) in [
    (TargetPlatform.macOS, const Locale('en'), 'Search outline'),
    (TargetPlatform.android, const Locale('ja'), '構成を検索'),
  ]) {
    _platformTest(
      'search filters cached outline labels on $platform',
      platform,
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpApp(tester, locale: locale, source: _source);
          final search = find.byKey(const ValueKey('document-outline-search'));
          expect(search, findsOneWidget);
          expect(
            find.bySemanticsIdentifier('document-outline-search'),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel(searchLabel), findsOneWidget);
          for (var index = 0; index < 7; index++) {
            expect(
              find.byKey(ValueKey('document-block-$index')),
              findsOneWidget,
            );
          }

          await tester.enterText(search, 'FIRST paragraph');
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('document-block-1')),
            findsOneWidget,
          );
          expect(
            (tester
                        .widget<ListTile>(
                          find.byKey(const ValueKey('document-block-1')),
                        )
                        .title!
                    as Text)
                .data,
            'First paragraph continues here',
          );
          for (final index in [0, 2, 3, 4, 5, 6]) {
            expect(
              find.byKey(ValueKey('document-block-$index')),
              findsNothing,
              reason: 'block $index should be filtered out',
            );
          }

          await tester.enterText(search, '   ');
          await tester.pumpAndSettle();
          for (var index = 0; index < 7; index++) {
            expect(
              find.byKey(ValueKey('document-block-$index')),
              findsOneWidget,
              reason: 'whitespace-only query is no filter',
            );
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  _platformTest(
    'a filtered match selects its exact source range',
    TargetPlatform.macOS,
    (tester) async {
      final controller = await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: _source,
      );
      await tester.enterText(
        find.byKey(const ValueKey('document-outline-search')),
        'beta',
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('document-block-3'));
      expect(entry, findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-2')), findsNothing);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final expected = parseDocumentBlocks(_source)[3];
      expect(
        controller.selection,
        TextSelection(baseOffset: expected.start, extentOffset: expected.end),
      );
      expect(controller.text, _source);
      expect(_focusesSource(tester), isTrue);
    },
  );

  for (final (locale, noMatches) in [
    (const Locale('en'), _noMatchesEn),
    (const Locale('ja'), _noMatchesJa),
  ]) {
    _platformTest(
      'a query with no matches shows the localized notice for $locale',
      TargetPlatform.macOS,
      (tester) async {
        await _pumpApp(tester, locale: locale, source: _source);
        final search = find.byKey(const ValueKey('document-outline-search'));
        await tester.enterText(search, 'no-such-heading');
        await tester.pumpAndSettle();
        expect(find.text(noMatches), findsOneWidget);
        expect(find.byKey(const ValueKey('document-block-0')), findsNothing);

        await tester.enterText(find.byKey(const ValueKey('source-text')), '');
        await tester.pumpAndSettle();
        expect(find.text(noMatches), findsOneWidget);
        expect(
          find.text(
            locale.languageCode == 'ja'
                ? '原文にはまだブロックがありません。'
                : 'No blocks in the source text yet.',
          ),
          findsNothing,
        );
      },
    );
  }

  for (final (locale, matchCap) in [
    (const Locale('en'), _matchCapEn),
    (const Locale('ja'), _matchCapJa),
  ]) {
    _platformTest(
      'a query above the entry cap shows the localized notice for $locale',
      TargetPlatform.macOS,
      (tester) async {
        final source = List<String>.generate(
          maxVisibleOutlineBlocks + 20,
          (index) => '## Heading $index',
        ).join('\n');
        await _pumpApp(tester, locale: locale, source: source);
        expect(
          find.text(locale.languageCode == 'ja' ? _entryCapJa : _entryCapEn),
          findsOneWidget,
        );
        expect(find.text(_truncatedNoticeEn), findsNothing);

        await tester.enterText(
          find.byKey(const ValueKey('document-outline-search')),
          'heading',
        );
        await tester.pumpAndSettle();
        expect(find.text(matchCap), findsOneWidget);
        expect(find.text(_entryCapEn), findsNothing);
        expect(find.text(_entryCapJa), findsNothing);
        expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
        expect(
          find.byKey(ValueKey('document-block-${maxVisibleOutlineBlocks - 1}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('document-block-$maxVisibleOutlineBlocks')),
          findsNothing,
        );
      },
    );
  }

  _platformTest(
    'editing the source refreshes filtered outline results',
    TargetPlatform.macOS,
    (tester) async {
      await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: '## Before\nOld body',
      );
      await tester.enterText(
        find.byKey(const ValueKey('document-outline-search')),
        'Before',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
      expect(
        (tester
                    .widget<ListTile>(
                      find.byKey(const ValueKey('document-block-0')),
                    )
                    .title!
                as Text)
            .data,
        'Before',
      );

      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        '## After\nNew body',
      );
      await tester.pumpAndSettle();
      expect(find.text(_noMatchesEn), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-0')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('document-outline-search')),
        'After',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
      expect(
        (tester
                    .widget<ListTile>(
                      find.byKey(const ValueKey('document-block-0')),
                    )
                    .title!
                as Text)
            .data,
        'After',
      );
      expect(tester.takeException(), isNull);
    },
  );

  _platformTest(
    'outline search follows the Android IME privacy setting',
    TargetPlatform.android,
    (tester) async {
      await _pumpApp(tester, locale: const Locale('en'), source: '## Heading');
      final search = find.byKey(const ValueKey('document-outline-search'));
      expect(
        tester.widget<TextField>(search).enableIMEPersonalizedLearning,
        isFalse,
      );

      final toggle = find.byKey(
        const ValueKey('android-ime-personalized-learning'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(search).enableIMEPersonalizedLearning,
        isTrue,
      );
    },
  );

  _platformTest(
    'a clipped block at the prefix cutoff is not offered as an exact range',
    TargetPlatform.macOS,
    (tester) async {
      final source = '## Complete\n${'x' * maxOutlineSourceLength}😀 trailing';
      expect(source.length, greaterThan(maxOutlineSourceLength));
      final controller = await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: source,
      );

      expect(find.text(_truncatedNoticeEn), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-1')), findsNothing);

      final expected = parseDocumentBlocks('## Complete').single;
      final entry = find.byKey(const ValueKey('document-block-0'));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        TextSelection(baseOffset: expected.start, extentOffset: expected.end),
      );
      expect(controller.text, source);
    },
  );

  _platformTest(
    'a paragraph continuing after a line terminator at the cutoff is not offered',
    TargetPlatform.macOS,
    (tester) async {
      final source = "${'x' * (maxOutlineSourceLength - 1)}\ncontinued\n";
      expect(source.codeUnitAt(maxOutlineSourceLength - 1), 0x0A);
      await _pumpApp(tester, locale: const Locale('en'), source: source);
      expect(find.text(_truncatedNoticeEn), findsOneWidget);
      expect(find.text('No blocks in the source text yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-0')), findsNothing);
    },
  );

  _platformTest(
    'a complete heading ending at the cutoff is still offered',
    TargetPlatform.macOS,
    (tester) async {
      const label = '## Target heading';
      final heading = label + 'z' * (maxOutlineSourceLength - label.length);
      expect(heading.length, maxOutlineSourceLength);
      final source = '$heading\nafter\n';
      final controller = await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: source,
      );
      expect(find.text(_truncatedNoticeEn), findsOneWidget);
      final entry = find.byKey(const ValueKey('document-block-0'));
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: maxOutlineSourceLength,
        ),
      );
      expect(find.byKey(const ValueKey('document-block-1')), findsNothing);
    },
  );

  _platformTest(
    'an open fence crossing a line terminator at the cutoff is not offered',
    TargetPlatform.macOS,
    (tester) async {
      const opening = '```\n';
      final source =
          '$opening${'x' * (maxOutlineSourceLength - opening.length - 1)}'
          '\ncode line\n```\n';
      expect(source.codeUnitAt(maxOutlineSourceLength - 1), 0x0A);
      await _pumpApp(tester, locale: const Locale('en'), source: source);
      expect(find.text(_truncatedNoticeEn), findsOneWidget);
      expect(find.text('No blocks in the source text yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-0')), findsNothing);
    },
  );

  for (final (locale, hint) in [
    (const Locale('en'), 'Review: number, link, placeholder'),
    (const Locale('ja'), '確認: 数字, リンク, プレースホルダー'),
  ]) {
    _platformTest(
      'review hints appear only on flagged outline entries for $locale',
      TargetPlatform.macOS,
      (tester) async {
        final source =
            '## Version 2 {name} https://example.com\n'
            '## Plain heading';
        await _pumpApp(tester, locale: locale, source: source);
        expect(find.text(hint), findsOneWidget);
        expect(
          find.textContaining(locale.languageCode == 'ja' ? '確認:' : 'Review:'),
          findsOneWidget,
        );
        final plain = tester.widget<ListTile>(
          find.byKey(const ValueKey('document-block-1')),
        );
        expect(plain.subtitle, isNull);
      },
    );
  }

  _platformTest(
    'the review-only filter keeps original indices and exact selection',
    TargetPlatform.macOS,
    (tester) async {
      final source =
          '## Plain one\n'
          '## Version 2 {name}\n'
          '## Plain two\n'
          '## See https://example.com';
      final controller = await _pumpApp(
        tester,
        locale: const Locale('en'),
        source: source,
      );
      await tester.tap(
        find.byKey(const ValueKey('document-outline-review-only')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('document-block-0')), findsNothing);
      expect(find.byKey(const ValueKey('document-block-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('document-block-2')), findsNothing);
      expect(find.byKey(const ValueKey('document-block-3')), findsOneWidget);

      final expected = parseDocumentBlocks(source)[1];
      await tester.tap(find.byKey(const ValueKey('document-block-1')));
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        TextSelection(baseOffset: expected.start, extentOffset: expected.end),
      );
    },
  );

  for (final (locale, notice) in [
    (const Locale('en'), 'No outline entries need local review.'),
    (const Locale('ja'), 'ローカルで確認が必要な構成の項目はありません。'),
  ]) {
    _platformTest(
      'review-only filter has a localized empty state for $locale',
      TargetPlatform.macOS,
      (tester) async {
        await _pumpApp(
          tester,
          locale: locale,
          source: '## Plain one\n## Plain two',
        );
        await tester.tap(
          find.byKey(const ValueKey('document-outline-review-only')),
        );
        await tester.pumpAndSettle();
        expect(find.text(notice), findsOneWidget);
      },
    );
  }
}
