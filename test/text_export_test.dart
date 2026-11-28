import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_document_exporter.dart';

class _Selector extends FileSelectorPlatform {
  FileSaveLocation? result;
  int calls = 0;
  List<XTypeGroup>? acceptedTypeGroups;
  SaveDialogOptions? options;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    calls++;
    this.acceptedTypeGroups = acceptedTypeGroups;
    this.options = options;
    return result;
  }
}

class _Writer {
  final writes = <(String, String, bool)>[];
  Object? failure;

  Future<void> write(String path, String text, bool replaceExisting) async {
    writes.add((path, text, replaceExisting));
    final error = failure;
    if (error != null) throw error;
  }
}

// Linux's access-ACL xattr ABI lets this test exercise a real named-user ACL
// without requiring the optional getfacl/setfacl command-line tools.
List<int>? _linuxAcl(
  FileSystemEntity entity, {
  String name = 'system.posix_acl_access',
  List<int>? value,
}) {
  final libc = DynamicLibrary.process();
  final get = libc
      .lookupFunction<
        IntPtr Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>, UintPtr),
        int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>, int)
      >('getxattr');
  final set = libc
      .lookupFunction<
        Int32 Function(
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
          UintPtr,
          Int32,
        ),
        int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>, int, int)
      >('setxattr');
  final errno = libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );
  return using((arena) {
    final path = entity.path.toNativeUtf8(allocator: arena);
    final nativeName = name.toNativeUtf8(allocator: arena);
    if (value != null) {
      final data = arena<Uint8>(value.length);
      data.asTypedList(value.length).setAll(0, value);
      expect(set(path, nativeName, data.cast(), value.length, 0), 0);
    }
    final size = get(path, nativeName, nullptr, 0);
    if (size < 0) {
      expect(errno().value, 61); // ENODATA only, not unsupported operations.
      return null;
    }
    expect(size, greaterThan(0));
    final data = arena<Uint8>(size);
    expect(get(path, nativeName, data.cast(), size), size);
    return data.asTypedList(size).toList();
  });
}

Future<String> _command(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    environment: environment,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return (result.stdout as String).trim();
}

Future<String> _powershell(
  String script, {
  Map<String, String>? environment,
}) => _command('pwsh.exe', [
  '-NoProfile',
  '-NonInteractive',
  '-Command',
  r"$ErrorActionPreference = 'Stop'; Import-Module Microsoft.PowerShell.Security -ErrorAction Stop; " +
      script,
], environment: environment);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform original;
  late _Selector selector;

  setUp(() {
    original = FileSelectorPlatform.instance;
    selector = _Selector();
    FileSelectorPlatform.instance = selector;
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
  });

  tearDown(() {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocalesTestValue();
  });

  Finder field(String key) => find.byKey(ValueKey(key));

  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> openWorkspace(
    WidgetTester tester,
    _Writer writer, {
    String source = '原文',
    String firstTranslation = 'Bonjour',
    String secondTranslation = 'Hello, 🌏',
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KotohaApp(exportText: writer.write));
    await tester.enterText(field('source-text'), source);
    await tester.enterText(field('translation-text-0'), firstTranslation);
    final addTranslation = find.text('Add translation');
    await tester.ensureVisible(addTranslation);
    await tester.tap(addTranslation);
    await tester.pumpAndSettle();
    await tester.enterText(field('target-language-1'), 'fr');
    await tester.enterText(field('translation-text-1'), secondTranslation);
  }

  test('replaces with exact UTF-8 bytes and removes staging', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}translation.txt';
    File(path).writeAsBytesSync(utf8.encode('previous contents'));

    await exportTextDocument(path, 'Hello, 🌏', true);

    expect(File(path).readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(directory.listSync().map((entity) => entity.path).toSet(), {path});
  });

  test('a new export contains exact bytes and removes staging', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}translation.txt';

    await exportTextDocument(path, 'Hello, 🌏', false);

    expect(File(path).readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(directory.listSync().map((entity) => entity.path).toSet(), {path});
  });

  test('replacement preserves POSIX mode 0600', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/translation.txt');
    file.writeAsStringSync('previous contents');
    await _command('chmod', ['600', file.path]);
    expect(file.statSync().mode & 0x1ff, 0x180);

    await exportTextDocument(file.path, 'Hello, 🌏', true);

    expect(file.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(file.statSync().mode & 0x1ff, 0x180);
    expect(directory.listSync().map((entity) => entity.path).toSet(), {
      file.path,
    });
  }, skip: !(Platform.isLinux || Platform.isMacOS));

  test('replacement supports a read-only POSIX destination', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/translation.txt')
      ..writeAsStringSync('previous contents');
    await _command('chmod', ['444', file.path]);

    await exportTextDocument(file.path, 'Hello, 🌏', true);

    expect(file.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(file.statSync().mode & 0xfff, 0x124);
    expect(directory.listSync().map((entity) => entity.path).toSet(), {
      file.path,
    });
  }, skip: !(Platform.isLinux || Platform.isMacOS));

  test('replacement preserves Linux access ACLs, not staged entries', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/translation.txt');
    file.writeAsStringSync('previous contents');
    // Linux POSIX ACL xattr version 2; entries are tag, permissions, uid/gid.
    // Deny uid 65534 even though other users can read: copying mode alone
    // would remove that protection. ACL_MASK and the owning group have no rights.
    final acl = ByteData(44)..setUint32(0, 2, Endian.little);
    final entries = [
      (1, 6, 0xffffffff),
      (2, 0, 65534),
      (4, 0, 0xffffffff),
      (16, 0, 0xffffffff),
      (32, 4, 0xffffffff),
    ];
    for (var index = 0; index < entries.length; index++) {
      final (tag, permissions, id) = entries[index];
      final offset = 4 + index * 8;
      acl.setUint16(offset, tag, Endian.little);
      acl.setUint16(offset + 2, permissions, Endian.little);
      acl.setUint32(offset + 4, id, Endian.little);
    }
    final before = _linuxAcl(file, value: acl.buffer.asUint8List());
    expect(before, isNotNull);
    final mode = file.statSync().mode & 0x1ff;

    await exportTextDocument(file.path, 'Hello, 🌏', true);

    expect(file.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(file.statSync().mode & 0x1ff, mode);
    expect(_linuxAcl(file), before);

    final plain = File('${directory.path}/plain.txt')..writeAsStringSync('old');
    await _command('chmod', ['640', plain.path]);
    expect(_linuxAcl(plain), isNull);
    // A staged ACL (e.g. inherited from the parent) must not grant a named
    // user access that the destination never granted.
    acl.setUint16(14, 4, Endian.little); // named user: read
    acl.setUint16(30, 4, Endian.little); // mask: read
    acl.setUint16(38, 0, Endian.little); // other: none
    await exportTextDocumentWithStagedWriter(plain.path, 'Hello, 🌏', true, (
      staged,
      sink,
      bytes,
    ) async {
      await sink.writeFrom(bytes);
      expect(_linuxAcl(staged, value: acl.buffer.asUint8List()), isNotNull);
    });
    expect(plain.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(plain.statSync().mode & 0x1ff, 0x1a0);
    expect(_linuxAcl(plain), isNull);
    expect(directory.listSync().map((entity) => entity.path).toSet(), {
      file.path,
      plain.path,
    });
  }, skip: !Platform.isLinux);

  test('new Linux exports inherit selected-directory ACL defaults', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    // Version-2 ACL: owner rw, named user 65534 read, group none, mask read,
    // and other none. Files created directly in this directory inherit it.
    final acl = ByteData(44)..setUint32(0, 2, Endian.little);
    final entries = [
      (1, 6, 0xffffffff),
      (2, 4, 65534),
      (4, 0, 0xffffffff),
      (16, 4, 0xffffffff),
      (32, 0, 0xffffffff),
    ];
    for (var index = 0; index < entries.length; index++) {
      final (tag, permissions, id) = entries[index];
      final offset = 4 + index * 8;
      acl.setUint16(offset, tag, Endian.little);
      acl.setUint16(offset + 2, permissions, Endian.little);
      acl.setUint32(offset + 4, id, Endian.little);
    }
    final defaultAcl = acl.buffer.asUint8List();
    _linuxAcl(directory, name: 'system.posix_acl_default', value: defaultAcl);
    final reference = File('${directory.path}/reference.txt')
      ..writeAsStringSync('reference');
    final expectedAcl = _linuxAcl(reference);
    expect(expectedAcl, isNotNull);
    final output = File('${directory.path}/translation.txt');

    await exportTextDocumentWithStagedWriter(output.path, 'Hello, 🌏', false, (
      staged,
      sink,
      bytes,
    ) async {
      expect(staged.parent.statSync().mode & 0x1ff, 0x1c0);
      final inherited = _linuxAcl(
        staged.parent,
        name: 'system.posix_acl_access',
      );
      expect(inherited, isNotNull);
      expect(
        ByteData.sublistView(Uint8List.fromList(inherited!))
            .getUint16(30, Endian.little),
        0,
      );
      await sink.writeFrom(bytes);
    });

    expect(output.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(output.statSync().mode & 0x1ff, reference.statSync().mode & 0x1ff);
    expect(_linuxAcl(output), expectedAcl);
    expect(directory.listSync().map((entity) => entity.path).toSet(), {
      reference.path,
      output.path,
    });
  }, skip: !Platform.isLinux);

  // These tests exercise native OS mechanisms only on their actual platform.
  // They are not evidence of macOS/Windows behavior when run on Linux.
  test('replacement preserves a macOS deny-read ACL privately while staging', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/translation.txt');
    file.writeAsStringSync('previous contents');
    await _command('chmod', ['+a', 'everyone deny read', file.path]);
    Future<List<String>> acl(String path) async => (await _command('ls', [
      '-le',
      path,
    ])).split('\n').skip(1).where((line) => line.trim().isNotEmpty).toList();
    final before = await acl(file.path);
    final mode = file.statSync().mode & 0xfff;
    expect(before, isNotEmpty);
    expect(before.join(), contains('everyone deny read'));

    await exportTextDocumentWithStagedWriter(file.path, 'Hello, 🌏', true, (
      staged,
      sink,
      bytes,
    ) async {
      // Preserve the data-deny ACL before plaintext reaches the stage.
      expect(await acl(staged.path), before);
      expect(bytes, utf8.encode('Hello, 🌏'));
      expect(
        () => staged.readAsBytesSync(),
        throwsA(isA<FileSystemException>()),
      );
      await sink.writeFrom(bytes);
    });

    expect(file.existsSync(), isTrue);
    expect(file.statSync().mode & 0xfff, mode);
    expect(await acl(file.path), before);
    // Remove the deny rule only after checking preservation, so the test can
    // verify the exact committed bytes without bypassing the ACL in production.
    await _command('chmod', ['-a', 'everyone deny read', file.path]);
    expect(file.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(await acl(file.path), isEmpty);
    expect(directory.listSync().map((entity) => entity.path).toSet(), {
      file.path,
    });
  }, skip: !Platform.isMacOS);

  test('an existing macOS file without an ACL does not inherit parent ACLs', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/translation.txt')
      ..writeAsStringSync('previous contents');
    Future<List<String>> acl(String path) async => (await _command('ls', [
      '-le',
      path,
    ])).split('\n').skip(1).where((line) => line.trim().isNotEmpty).toList();
    final before = await acl(file.path);
    final mode = file.statSync().mode & 0xfff;
    expect(before, isEmpty);
    await _command('chmod', [
      '+a',
      'everyone allow read,file_inherit,directory_inherit',
      directory.path,
    ]);
    final reference = File('${directory.path}/reference.txt')
      ..writeAsStringSync('reference');
    expect(await acl(reference.path), isNotEmpty);

    await exportTextDocumentWithStagedWriter(file.path, 'Hello, 🌏', true, (
      staged,
      sink,
      bytes,
    ) async {
      // Inherited parent ACEs must be removed before the stage receives bytes.
      expect(await acl(staged.path), isEmpty);
      await sink.writeFrom(bytes);
    });

    expect(file.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(file.statSync().mode & 0xfff, mode);
    expect(await acl(file.path), before);
  }, skip: !Platform.isMacOS);

  test('new macOS exports inherit selected-directory ACL defaults', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    await _command('chmod', [
      '+a',
      'everyone allow read,file_inherit,directory_inherit',
      directory.path,
    ]);
    final reference = File('${directory.path}/reference.txt')
      ..writeAsStringSync('reference');
    Future<List<String>> acl(String path) async => (await _command('ls', [
      '-le',
      path,
    ])).split('\n').skip(1).where((line) => line.trim().isNotEmpty).toList();
    final expectedAcl = await acl(reference.path);
    final output = File('${directory.path}/translation.txt');

    await exportTextDocument(output.path, 'Hello, 🌏', false);

    expect(output.readAsBytesSync(), utf8.encode('Hello, 🌏'));
    expect(await acl(output.path), expectedAcl);
  }, skip: !Platform.isMacOS);

  test(
    'new Windows exports inherit selected-directory DACL defaults',
    () async {
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final reference = File(
        '${directory.path}${Platform.pathSeparator}reference.txt',
      )..writeAsStringSync('reference');
      final output = File(
        '${directory.path}${Platform.pathSeparator}translation.txt',
      );
      Future<String> dacl(File file) async {
        final result = await _powershell(
          r"(Get-Acl -LiteralPath $env:KOTOHA_EXPORT_PATH).GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)",
          environment: {'KOTOHA_EXPORT_PATH': file.path},
        );
        return result;
      }

      final expectedDacl = await dacl(reference);

      await exportTextDocument(output.path, 'Hello, 🌏', false);

      expect(output.readAsBytesSync(), utf8.encode('Hello, 🌏'));
      expect(await dacl(output), expectedDacl);
    },
    skip: !Platform.isWindows,
  );

  test(
    'replacement preserves a protected Windows DACL before staging',
    () async {
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}translation.txt',
      );
      file.writeAsStringSync('previous contents');
      Future<String> powershell(String script, {String? stagedPath}) =>
          _powershell(
            r"$path = $env:KOTOHA_EXPORT_TEST_PATH; " + script,
            environment: {
              'KOTOHA_EXPORT_TEST_PATH': file.path,
              'KOTOHA_EXPORT_STAGE_PATH': ?stagedPath,
            },
          );
      await powershell(r"""
$acl = Get-Acl -LiteralPath $path;
$acl.SetAccessRuleProtection($true, $false);
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User;
$rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
  $owner, [System.Security.AccessControl.FileSystemRights]::FullControl,
  [System.Security.AccessControl.AccessControlType]::Allow);
$acl.SetAccessRule($rule);
Set-Acl -LiteralPath $path -AclObject $acl;
""");
      Future<String> dacl(String path, {String? stagedPath}) => powershell(r"""
$aclPath = if ($env:KOTOHA_EXPORT_STAGE_PATH) { $env:KOTOHA_EXPORT_STAGE_PATH } else { $path };
(Get-Acl -LiteralPath $aclPath).GetSecurityDescriptorSddlForm(
  [System.Security.AccessControl.AccessControlSections]::Access)
""", stagedPath: stagedPath);
      final before = await dacl(file.path);
      expect(before, contains('D:P')); // protected, unlike the parent's DACL

      await exportTextDocumentWithStagedWriter(file.path, 'Hello, 🌏', true, (
        staged,
        sink,
        bytes,
      ) async {
        expect(
          await dacl(file.path, stagedPath: staged.path),
          before,
          reason:
              'the staged file must be protected before plaintext is written',
        );
        await sink.writeFrom(bytes);
      });

      expect(file.readAsBytesSync(), utf8.encode('Hello, 🌏'));
      expect(await dacl(file.path), before);
      expect(directory.listSync().map((entity) => entity.path).toSet(), {
        file.path,
      });
    },
    skip: !Platform.isWindows,
  );

  test(
    'a partial staging write preserves the destination and is cleaned',
    () async {
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}translation.txt';
      final previousBytes = utf8.encode('previous destination contents');
      File(path).writeAsBytesSync(previousBytes);
      File? stagedFile;
      int? stagingDirectoryMode;

      await expectLater(
        exportTextDocumentWithStagedWriter(path, 'Hello, 🌏', true, (
          file,
          sink,
          bytes,
        ) async {
          stagedFile = file;
          stagingDirectoryMode = (await file.parent.stat()).mode;
          await sink.writeFrom(bytes.sublist(0, 4));
          throw const FileSystemException('injected staging failure');
        }),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(path).readAsBytesSync(), previousBytes);
      expect(stagedFile, isNotNull);
      expect(stagedFile!.existsSync(), isFalse);
      if (!Platform.isWindows) {
        expect(stagingDirectoryMode, isNotNull);
        expect(stagingDirectoryMode! & 0x1ff, 0x1c0);
      }
      expect(directory.listSync().map((entity) => entity.path).toSet(), {path});
    },
  );

  test(
    'an existing selected symlink still writes through to its target',
    () async {
      if (Platform.isWindows) return;
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final target = File(
        '${directory.path}${Platform.pathSeparator}target.txt',
      );
      final link = Link(
        '${directory.path}${Platform.pathSeparator}selected.txt',
      );
      target.writeAsBytesSync(utf8.encode('old target contents'));
      await _command('chmod', ['600', target.path]);
      await link.create(target.path);

      await exportTextDocument(link.path, 'Hello, 🌏', true);

      expect(target.readAsBytesSync(), utf8.encode('Hello, 🌏'));
      expect(target.statSync().mode & 0x1ff, 0x180);
      expect(
        await FileSystemEntity.type(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform exports only the chosen translation', (
      tester,
    ) async {
      await withPlatform(platform, () async {
        final writer = _Writer();
        selector.result = FileSaveLocation('/user/chosen/translation.txt');
        await openWorkspace(tester, writer);
        final exportButton = field('export-translation-1');
        await tester.ensureVisible(exportButton);
        expect(
          tester.widget<IconButton>(exportButton).tooltip,
          'Export translation 2',
        );

        await tester.tap(exportButton);
        await tester.pump();

        expect(writer.writes, [
          ('/user/chosen/translation.txt', 'Hello, 🌏', false),
        ]);
        expect(selector.calls, 1);
        expect(selector.acceptedTypeGroups, hasLength(1));
        expect(selector.acceptedTypeGroups!.single.extensions, ['txt']);
        expect(selector.acceptedTypeGroups!.single.uniformTypeIdentifiers, [
          'public.utf8-plain-text',
        ]);
        expect(selector.options!.suggestedName, 'translation.txt');
        expect(selector.options!.confirmButtonText, 'Export');
        expect(find.text('Translation exported.'), findsOneWidget);
        expect(
          tester.widget<TextField>(field('source-text')).controller!.text,
          '原文',
        );
        expect(
          tester
              .widget<TextField>(field('translation-text-0'))
              .controller!
              .text,
          'Bonjour',
        );
        expect(
          tester
              .widget<TextField>(field('translation-text-1'))
              .controller!
              .text,
          'Hello, 🌏',
        );
      });
    });
  }

  testWidgets('existing export path: Cancel writes nothing', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final destination = File(
        '${directory.path}${Platform.pathSeparator}translation.txt',
      )..writeAsStringSync('previous destination contents');
      final writer = _Writer();
      selector.result = FileSaveLocation(destination.path);
      await openWorkspace(tester, writer);

      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.text('Replace existing file?'), findsOneWidget);
      expect(
        find.text(
          'A file already exists at the selected path. Exporting will '
          'overwrite it. Continue?',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(writer.writes, isEmpty);
      expect(destination.readAsStringSync(), 'previous destination contents');
      expect(find.text('Translation exported.'), findsNothing);
      expect(selector.calls, 1);
    });
  });

  testWidgets('existing export path: confirm writes the translation', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final destination = File(
        '${directory.path}${Platform.pathSeparator}translation.txt',
      )..writeAsStringSync('previous destination contents');
      final writer = _Writer();
      selector.result = FileSaveLocation(destination.path);
      await openWorkspace(tester, writer);

      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      expect(find.text('Replace existing file?'), findsOneWidget);

      await tester.tap(field('export-overwrite-confirm'));
      await tester.pumpAndSettle();

      expect(writer.writes, [(destination.path, 'Hello, 🌏', true)]);
      // Only the injected writer runs here; the real destination is untouched.
      expect(destination.readAsStringSync(), 'previous destination contents');
      expect(find.text('Translation exported.'), findsOneWidget);
    });
  });

  testWidgets('missing export path has no overwrite dialog', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final directory = Directory.systemTemp.createTempSync('kotoha-export');
      addTearDown(() => directory.deleteSync(recursive: true));
      final destination =
          '${directory.path}${Platform.pathSeparator}translation.txt';
      expect(File(destination).existsSync(), isFalse);
      final writer = _Writer();
      selector.result = FileSaveLocation(destination);
      await openWorkspace(tester, writer);

      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.text('Replace existing file?'), findsNothing);
      expect(writer.writes, [(destination, 'Hello, 🌏', false)]);
      expect(find.text('Translation exported.'), findsOneWidget);
    });
  });

  test('a destination created during staging is not replaced', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}translation.txt';
    final inserted = utf8.encode('inserted after the existence check');
    expect(File(path).existsSync(), isFalse);

    await expectLater(
      exportTextDocumentWithStagedWriter(path, 'Hello, 🌏', false, (
        staged,
        sink,
        bytes,
      ) async {
        // A file appears after selection but before the exporter commits.
        File(path).writeAsBytesSync(inserted);
        await sink.writeFrom(bytes);
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(File(path).readAsBytesSync(), inserted);
    expect(directory.listSync().map((entity) => entity.path).toSet(), {path});
  });

  testWidgets('cancelling export leaves all drafts unchanged', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      await openWorkspace(tester, writer);
      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(selector.calls, 1);
      expect(writer.writes, isEmpty);
      expect(find.text('Translation exported.'), findsNothing);
      expect(find.text('Could not export the translation.'), findsNothing);
      expect(
        tester.widget<TextField>(field('source-text')).controller!.text,
        '原文',
      );
      expect(
        tester.widget<TextField>(field('translation-text-0')).controller!.text,
        'Bonjour',
      );
      expect(
        tester.widget<TextField>(field('translation-text-1')).controller!.text,
        'Hello, 🌏',
      );
    });
  });

  testWidgets('reports a file write failure without changing the draft', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer()..failure = const FileSystemException('denied');
      selector.result = FileSaveLocation('/user/chosen/translation.txt');
      await openWorkspace(tester, writer);
      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(find.text('Could not export the translation.'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('source-text')).controller!.text,
        '原文',
      );
      expect(
        tester.widget<TextField>(field('translation-text-0')).controller!.text,
        'Bonjour',
      );
      expect(
        tester.widget<TextField>(field('translation-text-1')).controller!.text,
        'Hello, 🌏',
      );
    });
  });

  testWidgets('an empty translation is not written', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      await openWorkspace(tester, writer, secondTranslation: '');
      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(find.text('Enter a translation to export.'), findsOneWidget);
      expect(selector.calls, 0);
      expect(writer.writes, isEmpty);
    });
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform has no desktop export action', (tester) async {
      await withPlatform(platform, () async {
        final writer = _Writer();
        await tester.pumpWidget(KotohaApp(exportText: writer.write));

        expect(field('export-translation-0'), findsNothing);
        expect(find.textContaining('Export writes only'), findsNothing);
        expect(writer.writes, isEmpty);
      });
    });
  }
}
