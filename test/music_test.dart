import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:winter_music/id3.dart';
import 'package:winter_music/library.dart';
import 'package:winter_music/models.dart';

List<int> _frame(String id, List<int> body) {
  final n = body.length;
  return [...ascii.encode(id), (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255, 0, 0, ...body];
}

List<int> _utf16(String s) {
  final out = <int>[1, 0xFF, 0xFE];
  for (final u in s.codeUnits) {
    out
      ..add(u & 255)
      ..add(u >> 8);
  }
  return out;
}

List<int> _cp1251(String s) => [
      0,
      for (final c in s.codeUnits) c >= 0x0410 && c <= 0x044F ? c - 0x0410 + 0xC0 : c,
    ];

void main() {
  test('теги ID3v2.3: UTF-16, Windows-1251, UTF-8 и обложка', () async {
    final cover = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
    final frames = [
      ..._frame('TIT2', _utf16('Группа крови')),
      ..._frame('TPE1', _cp1251('Кино')),
      ..._frame('TALB', [3, ...utf8.encode('Альбом №1')]),
      ..._frame('APIC', [0, ...ascii.encode('image/jpeg'), 0, 3, 0, ...cover]),
    ];
    final size = frames.length;
    final header = [
      ...ascii.encode('ID3'), 3, 0, 0,
      (size >> 21) & 127, (size >> 14) & 127, (size >> 7) & 127, size & 127,
    ];
    final dir = await Directory.systemTemp.createTemp('wm');
    final f = File('${dir.path}/t.mp3')..writeAsBytesSync([...header, ...frames, 0, 0, 0, 0]);
    final t = await readTags(f.path, withCover: true);
    expect(t.title, 'Группа крови');
    expect(t.artist, 'Кино');
    expect(t.album, 'Альбом №1');
    expect(t.cover, cover);
    final noCover = await readTags(f.path);
    expect(noCover.cover, isNull);
    await dir.delete(recursive: true);
  });

  test('файл без тегов не ломает чтение', () async {
    final dir = await Directory.systemTemp.createTemp('wm');
    final f = File('${dir.path}/x.mp3')..writeAsBytesSync([1, 2, 3]);
    final t = await readTags(f.path);
    expect(t.title, isNull);
    expect((await readTags('${dir.path}/нет.mp3')).title, isNull);
    await dir.delete(recursive: true);
  });

  test('плейлист сохраняется и читается', () {
    final p = Playlist('p1', 'В дорогу', [
      Track(id: '/music/a.mp3', title: 'A', artist: 'X', source: 'local', durationMs: 1000),
      Track(id: 'https://radio', title: 'Радио', source: 'radio', art: 'https://img'),
    ]);
    final back = Playlist.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map);
    expect(back.name, 'В дорогу');
    expect(back.tracks.length, 2);
    expect(back.tracks[0].durationMs, 1000);
    expect(back.tracks[1].isRadio, isTrue);
    expect(back.tracks[1].art, 'https://img');
    expect(back.tracks[0], p.tracks[0]);
  });

  test('длительность форматируется', () {
    expect(fmtDur(const Duration(seconds: 65)), '1:05');
    expect(fmtDur(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  test('резервная копия: лайки и плейлисты добавляются, ничего не теряется', () {
    final lib = Library.instance;
    lib.liked
      ..clear()
      ..add(Track(id: '/m/a.mp3', title: 'A', source: 'local'));
    lib.playlists
      ..clear()
      ..add(Playlist('p1', 'Старый', [Track(id: '/m/a.mp3', title: 'A', source: 'local')]));
    lib.folders.clear();
    final backup = jsonDecode(lib.exportBackup()) as Map;
    expect(backup['app'], 'winter-music');
    lib.liked.clear();
    lib.playlists.clear();
    final r = lib.mergeBackup({
      ...backup,
      'liked': [...(backup['liked'] as List), Track(id: '/m/b.mp3', title: 'B', source: 'local').toJson()],
      'folders': ['/storage/Music'],
    });
    expect(r.liked, 2);
    expect(r.playlists, 1);
    expect(r.folders, 1);
    expect(lib.playlists.single.name, 'Старый');
    expect(lib.playlists.single.tracks.single.title, 'A');
    final again = lib.mergeBackup(backup);
    expect(again.liked, 0, reason: 'повторно не дублирует');
    expect(lib.playlists.length, 1);
  });
}
