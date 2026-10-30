import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'id3.dart';
import 'library.dart';
import 'models.dart';

enum Repeat { off, all, one }

/// Плеер с очередью, перемешиванием и повтором.
class Player extends ChangeNotifier {
  Player._() {
    _p.onPlayerComplete.listen((_) => _complete());
    _p.onPositionChanged.listen((d) {
      position = d;
      notifyListeners();
    });
    _p.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });
    _p.onPlayerStateChanged.listen((s) {
      playing = s == PlayerState.playing;
      notifyListeners();
    });
    _p.onLog.listen((_) {}, onError: (Object e) {
      error = 'Не удалось воспроизвести: $e';
      loading = false;
      notifyListeners();
    });
  }
  static final Player instance = Player._();

  final AudioPlayer _p = AudioPlayer();
  final List<Track> queue = [];
  List<int> _order = [];
  int _pos = -1;
  bool shuffle = false;
  Repeat repeat = Repeat.off;
  bool playing = false, loading = false;
  Duration position = Duration.zero, duration = Duration.zero;
  String? error;
  double volume = 1;
  Timer? _sleep;
  DateTime? sleepAt;

  Track? get current => _pos >= 0 && _pos < _order.length ? queue[_order[_pos]] : null;

  Future<void> playList(List<Track> list, int index) async {
    queue
      ..clear()
      ..addAll(list);
    _order = List.generate(list.length, (i) => i);
    if (shuffle) {
      _order.remove(index);
      _order.shuffle();
      _order.insert(0, index);
      _pos = 0;
    } else {
      _pos = index;
    }
    await _start();
  }

  Future<void> _start() async {
    final t = current;
    if (t == null) return;
    error = null;
    loading = true;
    position = Duration.zero;
    duration = Duration(milliseconds: t.durationMs ?? 0);
    notifyListeners();
    try {
      await _p.stop();
      if (t.isLocal) {
        await _p.play(DeviceFileSource(t.id), volume: volume);
        if (t.cover == null && t.id.toLowerCase().endsWith('.mp3')) {
          readTags(t.id, withCover: true).then((tags) {
            t.cover = tags.cover;
            notifyListeners();
          });
        }
      } else {
        await _p.play(UrlSource(t.id), volume: volume);
      }
      Library.instance.played(t);
    } catch (e) {
      error = t.isRadio ? 'Станция не отвечает — попробуй другую' : 'Не удалось воспроизвести этот трек';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (playing) {
      await _p.pause();
    } else {
      await _p.resume();
    }
  }

  Future<void> next({bool auto = false}) async {
    if (_order.isEmpty) return;
    if (_pos < _order.length - 1) {
      _pos++;
    } else if (repeat == Repeat.all || !auto) {
      _pos = 0;
    } else {
      await _p.stop();
      return;
    }
    await _start();
  }

  Future<void> prev() async {
    if (_order.isEmpty) return;
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    _pos = _pos > 0 ? _pos - 1 : _order.length - 1;
    await _start();
  }

  void _complete() {
    if (repeat == Repeat.one) {
      _start();
    } else {
      next(auto: true);
    }
  }

  Future<void> seek(Duration d) => _p.seek(d);

  void toggleShuffle() {
    shuffle = !shuffle;
    final cur = _pos >= 0 && _pos < _order.length ? _order[_pos] : 0;
    if (shuffle) {
      _order = List.generate(queue.length, (i) => i)..remove(cur);
      _order.shuffle(math.Random());
      _order.insert(0, cur);
      _pos = 0;
    } else {
      _order = List.generate(queue.length, (i) => i);
      _pos = cur;
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = Repeat.values[(repeat.index + 1) % Repeat.values.length];
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v;
    await _p.setVolume(v);
    notifyListeners();
  }

  /// Таймер сна: остановить через [minutes] минут (0 — выключить).
  void sleepIn(int minutes) {
    _sleep?.cancel();
    sleepAt = null;
    if (minutes > 0) {
      sleepAt = DateTime.now().add(Duration(minutes: minutes));
      _sleep = Timer(Duration(minutes: minutes), () {
        _p.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Очередь в порядке воспроизведения (для экрана «Далее»).
  List<Track> get upNext => [for (var i = _pos + 1; i < _order.length; i++) queue[_order[i]]];

  void playNext(Track t) {
    if (current == null) {
      playList([t], 0);
      return;
    }
    queue.add(t);
    _order.insert(_pos + 1, queue.length - 1);
    notifyListeners();
  }
}
