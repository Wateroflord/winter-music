import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'id3.dart';
import 'models.dart';
import 'ui.dart';

const audioExt = ['.mp3', '.m4a', '.aac', '.flac', '.ogg', '.opus', '.wav', '.wma'];

/// Медиатека: найденные файлы, лайки, плейлисты.
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  final _store = JsonStore('music.json');
  final List<Track> local = [];
  final List<Track> liked = [];
  final List<Playlist> playlists = [];
  final List<Track> recent = [];
  final List<String> folders = [];
  bool scanning = false;
  String? error;

  Future<void> load() async {
    final j = await _store.read();
    local
      ..clear()
      ..addAll([for (final t in (j['local'] as List? ?? const [])) Track.fromJson(t as Map)]);
    liked
      ..clear()
      ..addAll([for (final t in (j['liked'] as List? ?? const [])) Track.fromJson(t as Map)]);
    recent
      ..clear()
      ..addAll([for (final t in (j['recent'] as List? ?? const [])) Track.fromJson(t as Map)]);
    playlists
      ..clear()
      ..addAll([for (final p in (j['playlists'] as List? ?? const [])) Playlist.fromJson(p as Map)]);
    folders
      ..clear()
      ..addAll([for (final f in (j['folders'] as List? ?? const [])) '$f']);
    notifyListeners();
    if (local.isEmpty) scan();
  }

  Future<void> save() => _store.write({
        'local': [for (final t in local) t.toJson()],
        'liked': [for (final t in liked) t.toJson()],
        'recent': [for (final t in recent.take(50)) t.toJson()],
        'playlists': [for (final p in playlists) p.toJson()],
        'folders': folders,
      });

  /// Резервная копия: лайки, плейлисты, папки (сами файлы музыки остаются на телефоне).
  String exportBackup() => const JsonEncoder.withIndent(' ').convert({
        'app': 'winter-music',
        'version': 1,
        'liked': [for (final t in liked) t.toJson()],
        'playlists': [for (final p in playlists) p.toJson()],
        'folders': folders,
      });

  /// Добавляет данные из копии к текущим (ничего не удаляет). Возвращает текст для пользователя.
  String importBackup(String raw) {
    final Object? j;
    try {
      j = jsonDecode(raw.trim());
    } catch (_) {
      return 'Это не файл резервной копии';
    }
    if (j is! Map || j['app'] != 'winter-music') return 'Это не копия Winter Music';
    final r = mergeBackup(j);
    _changed();
    if (r.folders > 0) scan();
    return 'Восстановлено: плейлистов ${r.playlists}, лайков ${r.liked}';
  }

  ({int liked, int playlists, int folders}) mergeBackup(Map j) {
    var nl = 0, np = 0, nf = 0;
    for (final t in (j['liked'] as List? ?? const [])) {
      if (t is! Map) continue;
      final tr = Track.fromJson(t);
      if (!liked.contains(tr)) {
        liked.add(tr);
        nl++;
      }
    }
    for (final p in (j['playlists'] as List? ?? const [])) {
      if (p is! Map) continue;
      final pl = Playlist.fromJson(p);
      final i = playlists.indexWhere((e) => e.id == pl.id);
      if (i >= 0) {
        playlists[i] = pl;
      } else {
        playlists.add(pl);
      }
      np++;
    }
    for (final f in (j['folders'] as List? ?? const [])) {
      if (!folders.contains('$f')) {
        folders.add('$f');
        nf++;
      }
    }
    return (liked: nl, playlists: np, folders: nf);
  }

  void _changed() {
    notifyListeners();
    save();
  }

  // ---------- лайки и плейлисты ----------

  bool isLiked(Track t) => liked.contains(t);

  void toggleLike(Track t) {
    isLiked(t) ? liked.remove(t) : liked.insert(0, t);
    _changed();
  }

  Playlist createPlaylist(String name) {
    final p = Playlist(DateTime.now().microsecondsSinceEpoch.toString(), name);
    playlists.add(p);
    _changed();
    return p;
  }

  void addTo(Playlist p, Track t) {
    if (!p.tracks.contains(t)) p.tracks.add(t);
    _changed();
  }

  void removeFrom(Playlist p, Track t) {
    p.tracks.remove(t);
    _changed();
  }

  void renamePlaylist(Playlist p, String name) {
    p.name = name;
    _changed();
  }

  void deletePlaylist(Playlist p) {
    playlists.remove(p);
    _changed();
  }

  void reorder(Playlist p, int from, int to) {
    final t = p.tracks.removeAt(from);
    p.tracks.insert(to > from ? to - 1 : to, t);
    _changed();
  }

  void played(Track t) {
    recent.remove(t);
    recent.insert(0, t);
    if (recent.length > 50) recent.removeLast();
    _changed();
  }

  // ---------- поиск файлов ----------

  List<String> get defaultFolders {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      return [if (home != null) '$home\\Music', if (home != null) '$home\\Downloads'];
    }
    return ['/storage/emulated/0/Music', '/storage/emulated/0/Download', '/storage/emulated/0/Telegram'];
  }

  Future<bool> _permission() async {
    if (!Platform.isAndroid) return true;
    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;
    final st = await Permission.storage.request();
    return st.isGranted;
  }

  Future<void> addFolder(String path) async {
    if (!folders.contains(path)) folders.add(path);
    await save();
    await scan();
  }

  void removeFolder(String path) {
    folders.remove(path);
    _changed();
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    notifyListeners();
    if (!await _permission()) {
      error = 'Нет доступа к музыке. Разреши доступ в настройках телефона.';
      scanning = false;
      notifyListeners();
      return;
    }
    final found = <Track>[];
    final seen = <String>{};
    for (final dir in {...defaultFolders, ...folders}) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      try {
        await for (final e in d.list(recursive: true, followLinks: false).handleError((_) {})) {
          if (e is! File) continue;
          final lower = e.path.toLowerCase();
          if (!audioExt.any(lower.endsWith) || !seen.add(e.path)) continue;
          final name = e.uri.pathSegments.last;
          final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
          String title = base, artist = '';
          if (base.contains(' - ')) {
            artist = base.substring(0, base.indexOf(' - ')).trim();
            title = base.substring(base.indexOf(' - ') + 3).trim();
          }
          var album = '';
          if (lower.endsWith('.mp3')) {
            final tags = await readTags(e.path);
            if ((tags.title ?? '').isNotEmpty) title = tags.title!;
            if ((tags.artist ?? '').isNotEmpty) artist = tags.artist!;
            album = tags.album ?? '';
          }
          found.add(Track(id: e.path, title: title, artist: artist, album: album, source: 'local'));
          if (found.length % 50 == 0) notifyListeners();
        }
      } catch (_) {}
    }
    found.sort((a, b) => '${a.artist} ${a.title}'.toLowerCase().compareTo('${b.artist} ${b.title}'.toLowerCase()));
    local
      ..clear()
      ..addAll(found);
    scanning = false;
    if (found.isEmpty) error = 'Музыка не найдена. Добавь папку с музыкой кнопкой «Папки».';
    _changed();
  }
}
