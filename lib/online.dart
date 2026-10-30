import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Интернет-радио: открытый каталог radio-browser.info (без ключей).
class RadioCatalog {
  static const _hosts = ['de1.api.radio-browser.info', 'fi1.api.radio-browser.info', 'nl1.api.radio-browser.info'];

  static Future<List<Track>> search({String name = '', String tag = '', String country = ''}) async {
    for (final h in _hosts) {
      try {
        final q = {
          'limit': '60',
          'hidebroken': 'true',
          'order': 'clickcount',
          'reverse': 'true',
          if (name.isNotEmpty) 'name': name,
          if (tag.isNotEmpty) 'tag': tag,
          if (country.isNotEmpty) 'countrycode': country,
        };
        final r = await http
            .get(Uri.https(h, '/json/stations/search', q), headers: {'User-Agent': 'WinterMusic/1.0'})
            .timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) continue;
        final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
        return [
          for (final s in list.whereType<Map>())
            if ('${s['url_resolved'] ?? ''}'.startsWith('http'))
              Track(
                id: '${s['url_resolved']}',
                title: '${s['name']}'.trim(),
                artist: [
                  if ('${s['country'] ?? ''}'.isNotEmpty) '${s['country']}',
                  if ('${s['tags'] ?? ''}'.isNotEmpty) '${s['tags']}'.split(',').take(3).join(', '),
                ].join(' · '),
                source: 'radio',
                art: '${s['favicon'] ?? ''}'.startsWith('http') ? '${s['favicon']}' : null,
              ),
        ];
      } catch (_) {}
    }
    throw Exception('Каталог радио не отвечает');
  }
}

/// Бесплатная легальная музыка из Internet Archive (коллекция netlabels — музыка с открытыми лицензиями).
class Archive {
  static Future<List<Map<String, String>>> albums(String query) async {
    final q = query.isEmpty ? 'collection:(netlabels) AND mediatype:(audio)' : '($query) AND collection:(netlabels) AND mediatype:(audio)';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': q,
      'fl[]': ['identifier', 'title', 'creator'],
      'rows': '40',
      'output': 'json',
      'sort[]': 'downloads desc',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final docs = ((jsonDecode(utf8.decode(r.bodyBytes)) as Map)['response'] as Map)['docs'] as List;
    String s(dynamic v) => v is List ? v.join(', ') : '${v ?? ''}';
    return [
      for (final d in docs.whereType<Map>()) {'id': s(d['identifier']), 'title': s(d['title']), 'creator': s(d['creator'])},
    ];
  }

  static String cover(String id) => 'https://archive.org/services/img/$id';

  static Future<List<Track>> tracks(Map<String, String> album) async {
    final id = album['id']!;
    final r = await http.get(Uri.https('archive.org', '/metadata/$id')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final files = ((jsonDecode(utf8.decode(r.bodyBytes)) as Map)['files'] as List? ?? const []).whereType<Map>();
    final out = <Track>[];
    for (final f in files) {
      final name = '${f['name']}';
      if (!name.toLowerCase().endsWith('.mp3')) continue;
      final format = '${f['format'] ?? ''}';
      if (format.contains('64Kbps') && files.any((g) => '${g['format']}' == 'VBR MP3')) continue;
      final len = double.tryParse('${f['length'] ?? ''}');
      out.add(Track(
        id: 'https://archive.org/download/$id/${Uri.encodeComponent(name).replaceAll('%2F', '/')}',
        title: '${f['title'] ?? name.replaceAll('.mp3', '')}',
        artist: '${f['artist'] ?? f['creator'] ?? album['creator'] ?? ''}',
        album: album['title'] ?? '',
        source: 'archive',
        art: cover(id),
        durationMs: len == null ? null : (len * 1000).round(),
      ));
    }
    return out;
  }
}
