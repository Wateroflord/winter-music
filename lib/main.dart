import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'backup_io.dart';
import 'library.dart';
import 'media.dart';
import 'models.dart';
import 'online.dart';
import 'player.dart';
import 'ui.dart';
import 'package:winter_core/winter_core.dart';

void main() => runWinterApp(repo: 'winter-music', appName: 'Winter Music', body: _main);

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMedia();
  runApp(WinterCrashBanner(child: const MusicApp()));
}

const _pink = Color(0xFFFF78AA);

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Winter Music',
        debugShowCheckedModeBanner: false,
        theme: winterTheme(_pink),
        home: const Home(),
      );
}

final lib = Library.instance;
final player = Player.instance;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    lib.load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const LibraryTab(), const OnlineTab(), const PlaylistsTab()];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(child: IndexedStack(index: tab, children: pages)),
          const MiniPlayer(),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: W.surface,
        indicatorColor: _pink.withValues(alpha: 0.25),
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_music_outlined), label: 'Моя музыка'),
          NavigationDestination(icon: Icon(Icons.public), label: 'Онлайн'),
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Плейлисты'),
        ],
      ),
    );
  }
}

// ---------------- Общие элементы ----------------

class Cover extends StatelessWidget {
  final Track? t;
  final double size;
  const Cover(this.t, {super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final t = this.t;
    Widget fallback() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.18),
            gradient: const LinearGradient(colors: [Color(0xFF2B4472), Color(0xFF7E2553)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Icon(t?.isRadio == true ? Icons.radio : Icons.music_note, color: Colors.white70, size: size * 0.5),
        );
    Widget child;
    if (t?.cover != null) {
      child = Image.memory(t!.cover!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback());
    } else if (t?.art != null) {
      child = Image.network(t!.art!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback());
    } else {
      return fallback();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(size * 0.18), child: child);
  }
}

class TrackTile extends StatelessWidget {
  final Track t;
  final VoidCallback onTap;
  final Playlist? inPlaylist;
  const TrackTile(this.t, {super.key, required this.onTap, this.inPlaylist});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([player, lib]),
        builder: (context, _) {
          final cur = player.current == t;
          return ListTile(
            onTap: onTap,
            leading: Cover(t, size: 46),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: W.body.copyWith(color: cur ? _pink : W.text, fontWeight: cur ? FontWeight.w700 : null)),
            subtitle: Text(t.artist.isEmpty ? (t.album.isEmpty ? (t.isLocal ? 'Файл' : '') : t.album) : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: W.small),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: Icon(lib.isLiked(t) ? Icons.favorite : Icons.favorite_border, color: lib.isLiked(t) ? _pink : W.muted, size: 20),
                onPressed: () => lib.toggleLike(t),
              ),
              IconButton(icon: const Icon(Icons.more_vert, color: W.muted, size: 20), onPressed: () => trackMenu(context, t, inPlaylist: inPlaylist)),
            ]),
          );
        },
      );
}

Future<void> trackMenu(BuildContext context, Track t, {Playlist? inPlaylist}) async {
  final v = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(t.title, style: W.h2), subtitle: Text(t.artist, style: W.small)),
        ListTile(leading: const Icon(Icons.playlist_add), title: const Text('Добавить в плейлист'), onTap: () => Navigator.pop(ctx, 'add')),
        ListTile(leading: const Icon(Icons.queue_play_next), title: const Text('Играть следующим'), onTap: () => Navigator.pop(ctx, 'next')),
        if (inPlaylist != null)
          ListTile(leading: const Icon(Icons.remove_circle_outline, color: W.bad), title: const Text('Убрать из плейлиста'), onTap: () => Navigator.pop(ctx, 'remove')),
      ]),
    ),
  );
  if (!context.mounted) return;
  if (v == 'add') await addToPlaylist(context, t);
  if (v == 'next') {
    player.playNext(t);
    toast(context, 'Будет играть следующим');
  }
  if (v == 'remove' && inPlaylist != null) lib.removeFrom(inPlaylist, t);
}

Future<void> addToPlaylist(BuildContext context, Track t) async {
  final p = await showModalBottomSheet<Playlist>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('В какой плейлист?', style: W.h2)),
        ListTile(
          leading: const Icon(Icons.add, color: _pink),
          title: const Text('Новый плейлист'),
          onTap: () async {
            final name = await askName(ctx, 'Новый плейлист', '');
            if (name != null && ctx.mounted) Navigator.pop(ctx, lib.createPlaylist(name));
          },
        ),
        for (final p in lib.playlists)
          ListTile(leading: const Icon(Icons.queue_music), title: Text(p.name), subtitle: Text('${p.tracks.length} треков'), onTap: () => Navigator.pop(ctx, p)),
      ]),
    ),
  );
  if (p != null) {
    lib.addTo(p, t);
    if (context.mounted) toast(context, 'Добавлено в «${p.name}»');
  }
}

Future<String?> askName(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: W.h2),
      content: TextField(controller: c, autofocus: true, style: W.body, onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

InputDecoration searchDeco(String hint) => InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: W.surface,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: W.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: W.border)),
    );

// ---------------- Моя музыка ----------------

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  final q = TextEditingController();

  Future<void> _folders() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Папки с музыкой', style: W.h2), subtitle: Text('Ищу музыку здесь и в стандартных папках (Музыка, Загрузки)', style: W.small)),
            for (final f in lib.folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f, style: W.small.copyWith(color: W.text)),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => set(() => lib.removeFolder(f))),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined, color: _pink),
              title: const Text('Добавить папку'),
              onTap: () async {
                final d = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Папка с музыкой');
                if (d != null) {
                  await lib.addFolder(d);
                  set(() {});
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: _pink),
              title: const Text('Пересканировать'),
              onTap: () {
                Navigator.pop(ctx);
                lib.scan();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.upload_file, color: _pink),
              title: const Text('Сохранить резервную копию'),
              subtitle: const Text('Лайки, плейлисты и папки — пригодится после переустановки', style: W.small),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final path = await BackupIO.save('winter-music-${BackupIO.stamp()}.json', lib.exportBackup());
                  if (path != null) messenger.showSnackBar(const SnackBar(content: Text('Копия сохранена')));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore, color: _pink),
              title: const Text('Восстановить из копии'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final text = await BackupIO.open();
                  if (text == null) return;
                  messenger.showSnackBar(SnackBar(content: Text(lib.importBackup(text))));
                  set(() {});
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Не удалось восстановить: $e')));
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final query = q.text.trim().toLowerCase();
        final list = query.isEmpty ? lib.local : lib.local.where((t) => '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(query)).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(children: [
              const Expanded(child: Text('Моя музыка', style: W.h1)),
              IconButton(tooltip: 'Папки', icon: const Icon(Icons.folder_open), onPressed: _folders),
              IconButton(
                tooltip: 'Перемешать всё',
                icon: const Icon(Icons.shuffle),
                onPressed: list.isEmpty
                    ? null
                    : () {
                        if (!player.shuffle) player.toggleShuffle();
                        player.playList(list, 0);
                      },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(controller: q, onChanged: (_) => setState(() {}), style: W.body, decoration: searchDeco('Поиск по названию, исполнителю, альбому')),
          ),
          if (lib.scanning) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(color: _pink)),
          if (!lib.scanning && lib.error != null && lib.local.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(lib.error!, textAlign: TextAlign.center, style: W.body),
                const SizedBox(height: 12),
                FilledButton(onPressed: _folders, child: const Text('Выбрать папку с музыкой')),
                const SizedBox(height: 8),
                const Text('А ещё можно слушать бесплатную музыку и радио на вкладке «Онлайн».', textAlign: TextAlign.center, style: W.small),
              ]),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => TrackTile(list[i], onTap: () => player.playList(list, i)),
            ),
          ),
          if (lib.local.isNotEmpty) Padding(padding: const EdgeInsets.all(4), child: Text('Треков: ${lib.local.length}', style: W.small)),
        ]);
      },
    );
  }
}

// ---------------- Онлайн ----------------

class OnlineTab extends StatefulWidget {
  const OnlineTab({super.key});

  @override
  State<OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<OnlineTab> {
  int mode = 0; // 0 — бесплатная музыка, 1 — радио
  final q = TextEditingController();
  String genre = '';
  bool loading = false;
  String? error;
  List<Map<String, String>> albums = [];
  List<Track> stations = [];

  static const genres = [
    ('', 'Популярное'),
    ('electronic', 'Электроника'),
    ('ambient', 'Эмбиент'),
    ('chiptune', 'Чиптюн'),
    ('lofi', 'Lo-fi'),
    ('rock', 'Рок'),
    ('jazz', 'Джаз'),
    ('classical', 'Классика'),
    ('hip hop', 'Хип-хоп'),
    ('metal', 'Метал'),
  ];

  static const radioTags = [
    ('', 'Популярные'),
    ('pop', 'Поп'),
    ('rock', 'Рок'),
    ('electronic', 'Электроника'),
    ('lofi', 'Lo-fi'),
    ('jazz', 'Джаз'),
    ('classical', 'Классика'),
    ('news', 'Новости'),
  ];
  String country = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final text = q.text.trim();
      if (mode == 0) {
        final parts = [if (genre.isNotEmpty) 'subject:($genre)', if (text.isNotEmpty) text];
        albums = await Archive.albums(parts.join(' AND '));
      } else {
        stations = await RadioCatalog.search(name: text, tag: genre, country: country);
      }
    } catch (e) {
      error = 'Нет связи. Проверь интернет и нажми «Обновить».';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final chips = mode == 0 ? genres : radioTags;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(children: [
          const Expanded(child: Text('Онлайн', style: W.h1)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.album_outlined), label: Text('Бесплатная музыка')),
            ButtonSegment(value: 1, icon: Icon(Icons.radio), label: Text('Радио')),
          ],
          selected: {mode},
          onSelectionChanged: (s) {
            mode = s.first;
            genre = '';
            _load();
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(controller: q, style: W.body, textInputAction: TextInputAction.search, onSubmitted: (_) => _load(), decoration: searchDeco(mode == 0 ? 'Исполнитель, альбом, жанр' : 'Название станции')),
      ),
      SizedBox(
        height: 42,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
          for (final g in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip2(g.$2, selected: genre == g.$1, onTap: () {
                genre = g.$1;
                _load();
              }),
            ),
          if (mode == 1)
            for (final c in [('UA', '🇺🇦'), ('PL', '🇵🇱'), ('RU', '🇷🇺'), ('US', '🇺🇸'), ('GB', '🇬🇧'), ('DE', '🇩🇪')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip2(c.$2, selected: country == c.$1, onTap: () {
                  country = country == c.$1 ? '' : c.$1;
                  _load();
                }),
              ),
        ]),
      ),
      if (loading) const LinearProgressIndicator(color: _pink),
      if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: W.body)),
      Expanded(
        child: mode == 0
            ? GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, childAspectRatio: 0.78, mainAxisSpacing: 10, crossAxisSpacing: 10),
                itemCount: albums.length,
                itemBuilder: (_, i) {
                  final a = albums[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumScreen(album: a))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(Archive.cover(a['id']!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: W.surface2, child: Icon(Icons.album, color: W.muted))),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(a['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: W.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(a['creator'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: W.small),
                    ]),
                  );
                },
              )
            : ListView.builder(
                itemCount: stations.length,
                itemBuilder: (_, i) => TrackTile(stations[i], onTap: () => player.playList(stations, i)),
              ),
      ),
      if (mode == 0)
        const Padding(
          padding: EdgeInsets.all(4),
          child: Text('Музыка с открытыми лицензиями из Internet Archive (netlabels)', style: W.small),
        ),
    ]);
  }
}

class AlbumScreen extends StatefulWidget {
  final Map<String, String> album;
  const AlbumScreen({super.key, required this.album});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<Track>? tracks;
  String? error;

  @override
  void initState() {
    super.initState();
    Archive.tracks(widget.album).then((t) => setState(() => tracks = t)).catchError((_) => setState(() => error = 'Не удалось загрузить альбом'));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    final t = tracks;
    return Scaffold(
      appBar: AppBar(title: Text(a['title'] ?? '')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(Archive.cover(a['id']!), width: 110, height: 110, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 110, height: 110))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] ?? '', style: W.h2),
                Text(a['creator'] ?? '', style: W.small),
                const SizedBox(height: 10),
                Row(children: [
                  FilledButton.icon(onPressed: t == null || t.isEmpty ? null : () => player.playList(t, 0), icon: const Icon(Icons.play_arrow), label: const Text('Слушать')),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Сохранить альбом как плейлист',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: t == null || t.isEmpty
                        ? null
                        : () {
                            final p = lib.createPlaylist(a['title'] ?? 'Альбом');
                            for (final x in t) {
                              lib.addTo(p, x);
                            }
                            toast(context, 'Плейлист «${p.name}» создан');
                          },
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        if (error != null) Text(error!, style: W.body),
        if (t == null && error == null) const LinearProgressIndicator(color: _pink),
        Expanded(child: ListView.builder(itemCount: t?.length ?? 0, itemBuilder: (_, i) => TrackTile(t![i], onTap: () => player.playList(t, i)))),
        const MiniPlayer(),
      ]),
    );
  }
}

// ---------------- Плейлисты ----------------

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lib,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
          Row(children: [
            const Expanded(child: Text('Плейлисты', style: W.h1)),
            IconButton(
              tooltip: 'Новый плейлист',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final n = await askName(context, 'Новый плейлист', '');
                if (n != null) lib.createPlaylist(n);
              },
            ),
          ]),
          const SizedBox(height: 8),
          _tile(context, Icons.favorite, 'Любимые', '${lib.liked.length} треков', () => _open(context, null, 'Любимые', lib.liked)),
          _tile(context, Icons.history, 'Недавно слушал', '${lib.recent.length} треков', () => _open(context, null, 'Недавно слушал', lib.recent)),
          for (final p in lib.playlists) _tile(context, Icons.queue_music, p.name, '${p.tracks.length} треков', () => _open(context, p, p.name, p.tracks)),
          if (lib.playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text('Создай плейлист кнопкой «+» или добавляй треки через меню ⋮ у трека.', textAlign: TextAlign.center, style: W.small),
            ),
        ]),
      );

  Widget _tile(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: WCard(
          onTap: onTap,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFF7E2553), Color(0xFF2B4472)])),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: W.h2), Text(sub, style: W.small)])),
            const Icon(Icons.chevron_right, color: W.muted),
          ]),
        ),
      );

  void _open(BuildContext context, Playlist? p, String title, List<Track> tracks) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: p, title: title, tracks: tracks)));
}

class PlaylistScreen extends StatelessWidget {
  final Playlist? playlist;
  final String title;
  final List<Track> tracks;
  const PlaylistScreen({super.key, this.playlist, required this.title, required this.tracks});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lib,
        builder: (context, _) {
          final p = playlist;
          return Scaffold(
            appBar: AppBar(title: Text(p?.name ?? title), actions: [
              if (p != null)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final n = await askName(context, 'Название', p.name);
                      if (n != null) lib.renamePlaylist(p, n);
                    } else if (v == 'delete' && await confirmDialog(context, 'Удалить плейлист?', 'Треки останутся в медиатеке.', ok: 'Удалить')) {
                      lib.deletePlaylist(p);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
                  ],
                ),
            ]),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Text('${tracks.length} треков', style: W.small),
                  const Spacer(),
                  FilledButton.icon(onPressed: tracks.isEmpty ? null : () => player.playList(tracks, 0), icon: const Icon(Icons.play_arrow), label: const Text('Слушать')),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            if (!player.shuffle) player.toggleShuffle();
                            player.playList(tracks, 0);
                          },
                  ),
                ]),
              ),
              Expanded(
                child: p == null
                    ? ListView.builder(itemCount: tracks.length, itemBuilder: (_, i) => TrackTile(tracks[i], onTap: () => player.playList(tracks, i)))
                    : ReorderableListView.builder(
                        itemCount: p.tracks.length,
                        onReorder: (a, b) => lib.reorder(p, a, b),
                        itemBuilder: (_, i) => TrackTile(p.tracks[i], key: ValueKey(p.tracks[i].id), inPlaylist: p, onTap: () => player.playList(p.tracks, i)),
                      ),
              ),
              const MiniPlayer(),
            ]),
          );
        },
      );
}

// ---------------- Плеер ----------------

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final t = player.current;
          if (t == null) return const SizedBox();
          final total = player.duration.inMilliseconds;
          return Material(
            color: W.surface2,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayerScreen())),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: total > 0 ? player.position.inMilliseconds / total : (t.isRadio ? null : 0), minHeight: 2, color: _pink, backgroundColor: W.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(children: [
                    Cover(t, size: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: W.body.copyWith(fontWeight: FontWeight.w700)),
                        Text(player.error ?? t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: W.small.copyWith(color: player.error != null ? W.bad : null)),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.skip_previous), onPressed: player.prev),
                    player.loading
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(icon: Icon(player.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36, color: _pink), onPressed: player.toggle),
                    IconButton(icon: const Icon(Icons.skip_next), onPressed: player.next),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([player, lib]),
        builder: (context, _) {
          final t = player.current;
          if (t == null) return const Scaffold();
          final total = player.duration;
          final pos = player.position > total && total > Duration.zero ? total : player.position;
          return Scaffold(
            appBar: AppBar(
              title: Text(t.isRadio ? 'Радио' : 'Сейчас играет'),
              actions: [
                PopupMenuButton<int>(
                  icon: Icon(Icons.bedtime_outlined, color: player.sleepAt != null ? _pink : null),
                  tooltip: 'Таймер сна',
                  onSelected: player.sleepIn,
                  itemBuilder: (_) => [
                    for (final m in [0, 15, 30, 45, 60, 90]) PopupMenuItem(value: m, child: Text(m == 0 ? 'Выключить таймер' : 'Остановить через $m мин')),
                  ],
                ),
                IconButton(tooltip: 'Очередь', icon: const Icon(Icons.queue_music), onPressed: () => _queue(context)),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      const Spacer(),
                      LayoutBuilder(builder: (_, box) => Cover(t, size: box.maxWidth.clamp(0.0, 340.0))),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: W.h1.copyWith(fontSize: 22)),
                            Text(t.artist.isEmpty ? t.album : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: W.body.copyWith(color: W.muted)),
                          ]),
                        ),
                        IconButton(
                          icon: Icon(lib.isLiked(t) ? Icons.favorite : Icons.favorite_border, color: lib.isLiked(t) ? _pink : W.muted, size: 28),
                          onPressed: () => lib.toggleLike(t),
                        ),
                        IconButton(icon: const Icon(Icons.playlist_add, size: 28), onPressed: () => addToPlaylist(context, t)),
                      ]),
                      if (player.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(player.error!, style: W.small.copyWith(color: W.bad))),
                      if (player.sleepAt != null)
                        Text('Остановлю в ${player.sleepAt!.hour}:${player.sleepAt!.minute.toString().padLeft(2, '0')}', style: W.small.copyWith(color: _pink)),
                      const SizedBox(height: 12),
                      if (!t.isRadio) ...[
                        Slider(
                          activeColor: _pink,
                          value: total.inMilliseconds == 0 ? 0 : pos.inMilliseconds / total.inMilliseconds,
                          onChanged: total.inMilliseconds == 0 ? null : (v) => player.seek(total * v),
                        ),
                        Row(children: [Text(fmtDur(pos), style: W.small), const Spacer(), Text(fmtDur(total), style: W.small)]),
                      ] else
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('● Прямой эфир', style: TextStyle(color: _pink, fontWeight: FontWeight.w700))),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        IconButton(icon: Icon(Icons.shuffle, color: player.shuffle ? _pink : W.muted), onPressed: player.toggleShuffle),
                        IconButton(iconSize: 40, icon: const Icon(Icons.skip_previous), onPressed: player.prev),
                        player.loading
                            ? const SizedBox(width: 72, height: 72, child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
                            : IconButton(iconSize: 72, icon: Icon(player.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: _pink), onPressed: player.toggle),
                        IconButton(iconSize: 40, icon: const Icon(Icons.skip_next), onPressed: player.next),
                        IconButton(
                          icon: Icon(player.repeat == Repeat.one ? Icons.repeat_one : Icons.repeat, color: player.repeat == Repeat.off ? W.muted : _pink),
                          onPressed: player.cycleRepeat,
                        ),
                      ]),
                      Row(children: [
                        const Icon(Icons.volume_down, color: W.muted),
                        Expanded(child: Slider(value: player.volume, activeColor: _pink, onChanged: player.setVolume)),
                        const Icon(Icons.volume_up, color: W.muted),
                      ]),
                      const Spacer(),
                      if (Platform.isAndroid)
                        const Text('Музыка играет и при выключенном экране, пока приложение не закрыто.', style: W.small, textAlign: TextAlign.center),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );

  void _queue(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => ListenableBuilder(
          listenable: player,
          builder: (ctx, _) {
            final next = player.upNext;
            return SafeArea(
              child: ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('Далее', style: W.h2)),
                if (next.isEmpty) const ListTile(title: Text('Очередь пуста', style: W.small)),
                for (final t in next.take(50)) ListTile(leading: Cover(t, size: 36), title: Text(t.title, maxLines: 1, style: W.body), subtitle: Text(t.artist, maxLines: 1, style: W.small)),
              ]),
            );
          },
        ),
      );
}
