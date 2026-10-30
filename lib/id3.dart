import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Метаданные из тегов ID3v2 (MP3): название, исполнитель, альбом, обложка.
class Tags {
  String? title, artist, album;
  Uint8List? cover;
}

int _syncsafe(List<int> b, int o) => (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];
int _be32(List<int> b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

String _text(List<int> d) {
  if (d.isEmpty) return '';
  final enc = d[0];
  final body = d.sublist(1);
  String s;
  try {
    if (enc == 1 || enc == 2) {
      // UTF-16 (с BOM или без)
      var bytes = body;
      var le = true;
      if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        le = false;
        bytes = bytes.sublist(2);
      } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        bytes = bytes.sublist(2);
      } else if (enc == 2) {
        le = false;
      }
      final units = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        units.add(le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
      }
      s = String.fromCharCodes(units);
    } else if (enc == 3) {
      s = utf8.decode(body, allowMalformed: true);
    } else {
      // Latin-1, но часто это Windows-1251 у русских файлов.
      s = _cp1251(body);
    }
  } catch (_) {
    s = '';
  }
  return s.replaceAll('\u0000', '').trim();
}

String _cp1251(List<int> b) {
  final sb = StringBuffer();
  for (final c in b) {
    if (c < 0x80) {
      sb.writeCharCode(c);
    } else if (c >= 0xC0) {
      sb.writeCharCode(0x0410 + (c - 0xC0)); // А–я
    } else if (c == 0xA8) {
      sb.write('Ё');
    } else if (c == 0xB8) {
      sb.write('ё');
    } else {
      sb.writeCharCode(c);
    }
  }
  return sb.toString();
}

Future<Tags> readTags(String path, {bool withCover = false}) async {
  final t = Tags();
  RandomAccessFile? f;
  try {
    f = await File(path).open();
    final head = await f.read(10);
    if (head.length < 10 || head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) return t; // "ID3"
    final ver = head[3];
    final size = _syncsafe(head, 6);
    final data = await f.read(size.clamp(0, withCover ? 4 << 20 : 256 << 10));
    var i = 0;
    while (i + 10 <= data.length) {
      final id = String.fromCharCodes(data.sublist(i, i + 4));
      if (id.codeUnits.any((c) => c == 0)) break;
      final fsize = ver >= 4 ? _syncsafe(data, i + 4) : _be32(data, i + 4);
      if (fsize <= 0 || i + 10 + fsize > data.length) break;
      final body = data.sublist(i + 10, i + 10 + fsize);
      switch (id) {
        case 'TIT2':
          t.title = _text(body);
        case 'TPE1':
          t.artist = _text(body);
        case 'TALB':
          t.album = _text(body);
        case 'APIC':
          if (withCover && t.cover == null) {
            // encoding, mime\0, type, description\0, data
            final enc = body[0];
            var p = 1;
            while (p < body.length && body[p] != 0) {
              p++;
            }
            p += 2; // \0 + тип картинки
            if (enc == 1 || enc == 2) {
              while (p + 1 < body.length && !(body[p] == 0 && body[p + 1] == 0)) {
                p += 2;
              }
              p += 2;
            } else {
              while (p < body.length && body[p] != 0) {
                p++;
              }
              p += 1;
            }
            if (p < body.length) t.cover = Uint8List.fromList(body.sublist(p));
          }
      }
      i += 10 + fsize;
    }
  } catch (_) {
  } finally {
    await f?.close();
  }
  return t;
}
