import 'dart:convert';
import 'dart:typed_data';

/// Трек: файл на устройстве, трек из интернет-архива или радиостанция.
class Track {
  final String id; // путь к файлу или ссылка
  final String title, artist, album;
  final String source; // local | archive | radio
  final String? art; // ссылка на обложку
  final int? durationMs;
  Uint8List? cover; // обложка из файла (не сохраняется)

  Track({required this.id, required this.title, this.artist = '', this.album = '', required this.source, this.art, this.durationMs});

  bool get isRadio => source == 'radio';
  bool get isLocal => source == 'local';

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'a': artist, 'al': album, 's': source, if (art != null) 'art': art, if (durationMs != null) 'd': durationMs};

  static Track fromJson(Map j) => Track(
        id: '${j['id']}',
        title: '${j['t'] ?? ''}',
        artist: '${j['a'] ?? ''}',
        album: '${j['al'] ?? ''}',
        source: '${j['s'] ?? 'local'}',
        art: j['art'] as String?,
        durationMs: (j['d'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Playlist {
  final String id;
  String name;
  final List<Track> tracks;
  Playlist(this.id, this.name, [List<Track>? t]) : tracks = t ?? [];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'tracks': [for (final t in tracks) t.toJson()]};
  static Playlist fromJson(Map j) => Playlist('${j['id']}', '${j['name']}', [for (final t in (j['tracks'] as List? ?? const [])) Track.fromJson(t as Map)]);
}

String fmtDur(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String prettyJson(Object o) => const JsonEncoder.withIndent(' ').convert(o);
