import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/files/files_controller.dart';

import 'fakes.dart';

void main() {
  late FakeRuntime rt;
  late FilesController c;

  setUp(() {
    rt = FakeRuntime();
    rt.listings = {
      '/root': [file('b.txt'), file('src', isDir: true), file('a.txt')],
      '/root/src': [file('main.py', dir: '/root/src')],
    };
    c = FilesController(rt);
  });

  test('lists folders before files, alphabetically, even if the runtime does not', () async {
    await c.open('/root');
    expect(c.entries.map((e) => e.name), ['src', 'a.txt', 'b.txt']);
    expect(c.path, '/root');
  });

  test('open and up navigate, and up stops at /root', () async {
    await c.open('/root/src');
    expect(c.path, '/root/src');
    await c.up();
    expect(c.path, '/root');
    await c.up();
    expect(c.path, '/root');
    expect(c.canGoUp, isFalse);
  });

  test('breadcrumbs', () async {
    await c.open('/root/src');
    expect(c.crumbs.map((b) => b.$1), ['root', 'src']);
    expect(c.crumbs.map((b) => b.$2), ['/root', '/root/src']);
  });

  test('delete of a selection calls the runtime once per path and refreshes', () async {
    await c.open('/root');
    c.toggle('/root/a.txt');
    c.toggle('/root/b.txt');
    expect(c.selection, {'/root/a.txt', '/root/b.txt'});
    await c.deleteSelection();
    expect(rt.log.where((l) => l.startsWith('delete')), ['delete /root/a.txt', 'delete /root/b.txt']);
    expect(c.selection, isEmpty);
    expect(rt.log.last, 'list /root');
  });

  test('an error keeps the old listing and is reported', () async {
    await c.open('/root');
    rt.fileError = PlatformException(code: 'outside_sandbox', message: 'nope');
    await c.open('/root/src');
    expect(c.error, 'nope');
    expect(c.path, '/root');
    expect(c.entries, isNotEmpty);
    rt.fileError = null;
    await c.refresh();
    expect(c.error, isNull);
  });

  test('copy then paste into another folder, cut then paste moves', () async {
    await c.open('/root');
    c.toggle('/root/a.txt');
    c.copySelection();
    await c.open('/root/src');
    await c.paste();
    expect(rt.log, contains('copy /root/a.txt /root/src'));
    expect(c.hasClipboard, isTrue); // a copy can be pasted again
    c.toggle('/root/src/main.py');
    c.cutSelection();
    await c.open('/root');
    await c.paste();
    expect(rt.log, contains('move /root/src/main.py /root'));
    expect(c.hasClipboard, isFalse); // a cut is single-use
  });

  test('names with a slash or empty names are rejected before reaching the runtime', () async {
    await c.open('/root');
    await c.createFolder('a/b');
    await c.createFile('  ');
    await c.rename(c.entries.first, '..');
    expect(rt.log.where((l) => l.startsWith('mkdir') || l.startsWith('create') || l.startsWith('rename')), isEmpty);
    expect(c.error, isNotNull);
  });

  test('create folder and file use the current folder', () async {
    await c.open('/root/src');
    await c.createFolder('lib');
    await c.createFile('x.py');
    expect(rt.log, containsAll(['mkdir /root/src/lib', 'create /root/src/x.py']));
  });
}
