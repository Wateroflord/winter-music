import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'player.dart';

/// Управление музыкой с экрана блокировки, из шторки уведомлений и кнопками
/// наушников. Пока играет музыка, Android держит приложение «на переднем плане»
/// и не выгружает его в фоне.
class WinterAudioHandler extends BaseAudioHandler with SeekHandler {
  WinterAudioHandler(this._player) {
    _player.addListener(_sync);
    _sync();
  }

  final Player _player;
  String? _lastId;

  void _sync() {
    final t = _player.current;
    if (t == null) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
      return;
    }
    if (t.id != _lastId || mediaItem.value?.duration != _dur()) {
      _lastId = t.id;
      mediaItem.add(MediaItem(
        id: t.id,
        title: t.title.isEmpty ? 'Без названия' : t.title,
        artist: t.isRadio ? 'Радио' : (t.artist.isEmpty ? null : t.artist),
        album: t.album.isEmpty ? null : t.album,
        duration: _dur(),
        artUri: t.art == null ? null : Uri.tryParse(t.art!),
      ));
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {
        if (!t.isRadio) MediaAction.seek,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _player.loading ? AudioProcessingState.loading : AudioProcessingState.ready,
      playing: _player.playing,
      updatePosition: _player.position,
    ));
  }

  Duration? _dur() => _player.current?.isRadio == true || _player.duration == Duration.zero ? null : _player.duration;

  @override
  Future<void> play() async {
    if (!_player.playing) await _player.toggle();
  }

  @override
  Future<void> pause() async {
    if (_player.playing) await _player.toggle();
  }

  @override
  Future<void> stop() async {
    if (_player.playing) await _player.toggle();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.prev();

  @override
  Future<void> seek(Duration position) => _player.seek(position);
}

/// Подключает управление с экрана блокировки (только на Android).
Future<void> initMedia() async {
  if (!Platform.isAndroid) return;
  try {
    await AudioService.init(
      builder: () => WinterAudioHandler(Player.instance),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.winterhub.winter_music.audio',
        androidNotificationChannelName: 'Winter Music',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (_) {
    // Если не получилось — музыка всё равно играет, просто без шторки.
  }
}
