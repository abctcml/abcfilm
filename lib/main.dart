import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

const Color accentRed = Color(0xFFE50914);
const Color pageBg = Color(0xFF09090D);
const Color panelBg = Color(0xFF18181F);
const String apiBase = 'https://phim.nguonc.com/api';

void main() => runApp(const AbcFilmApp());

class AbcFilmApp extends StatelessWidget {
  const AbcFilmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'abcfilm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: pageBg,
        colorScheme: const ColorScheme.dark(
          primary: accentRed,
          secondary: accentRed,
          surface: panelBg,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: pageBg,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF111116),
          indicatorColor: accentRed.withValues(alpha: .18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) =>
              TextStyle(
                color: states.contains(WidgetState.selected)
                    ? Colors.white
                    : Colors.white60,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w400,
              )),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class Movie {
  final String name;
  final String slug;
  final String poster;
  final String thumb;
  final String originName;
  final String year;
  final String description;
  final String currentEpisode;
  final String totalEpisodes;
  final String quality;
  final List<dynamic> episodes;

  const Movie({
    required this.name,
    required this.slug,
    this.poster = '',
    this.thumb = '',
    this.originName = '',
    this.year = '',
    this.description = '',
    this.currentEpisode = '',
    this.totalEpisodes = '',
    this.quality = '',
    this.episodes = const [],
  });

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        name: '${j['name'] ?? 'Chưa có tên'}',
        slug: '${j['slug'] ?? ''}',
        poster: '${j['poster_url'] ?? ''}',
        thumb: '${j['thumb_url'] ?? ''}',
        originName: '${j['original_name'] ?? j['origin_name'] ?? ''}',
        year: '${j['year'] ?? ''}',
        description: '${j['description'] ?? j['content'] ?? ''}',
        currentEpisode: '${j['current_episode'] ?? j['episode_current'] ?? ''}',
        totalEpisodes: '${j['total_episodes'] ?? j['episode_total'] ?? ''}',
        quality: '${j['quality'] ?? ''}',
        episodes: j['episodes'] is List ? j['episodes'] as List<dynamic> : const [],
      );

  String get image => poster.isNotEmpty ? poster : thumb;
}

class NguonCService {
  static Future<Map<String, dynamic>> getJson(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Máy chủ trả về mã ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) throw Exception('Dữ liệu API không hợp lệ');
    return body;
  }

  static Future<List<Movie>> latest(int page) async {
    final data = await getJson('$apiBase/films/phim-moi-cap-nhat?page=$page');
    final items = data['items'];
    if (items is! List) return [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(Movie.fromJson)
        .where((m) => m.slug.isNotEmpty)
        .toList();
  }

  static Future<Movie> detail(String slug) async {
    final data = await getJson('$apiBase/film/${Uri.encodeComponent(slug)}');
    final raw = data['movie'];
    if (raw is Map<String, dynamic>) {
      final merged = Map<String, dynamic>.from(raw);
      merged['episodes'] = data['episodes'] ?? raw['episodes'] ?? [];
      return Movie.fromJson(merged);
    }
    throw Exception('Không tìm thấy thông tin phim');
  }

  static Future<List<Movie>> search(String keyword) async {
    // API search có thể thay đổi/không khả dụng; lọc kết quả từ các trang mới cập nhật.
    final result = <Movie>[];
    final needle = keyword.toLowerCase().trim();
    for (var page = 1; page <= 3; page++) {
      final items = await latest(page);
      result.addAll(items.where((m) => m.name.toLowerCase().contains(needle) ||
          m.originName.toLowerCase().contains(needle)));
      if (items.isEmpty) break;
    }
    return result;
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  final pages = const [DiscoverPage(), SearchPage(), FavoritesPage()];
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Trang chủ'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Tìm kiếm'),
            NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Yêu thích'),
          ],
        ),
      );
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final ScrollController scroll = ScrollController();
  final List<Movie> movies = [];
  int page = 1;
  bool loading = false;
  bool hasMore = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadMore();
    scroll.addListener(() {
      if (scroll.position.pixels >= scroll.position.maxScrollExtent - 500) loadMore();
    });
  }

  Future<void> loadMore({bool refresh = false}) async {
    if (loading || (!hasMore && !refresh)) return;
    setState(() {
      loading = true;
      error = null;
      if (refresh) {
        movies.clear();
        page = 1;
        hasMore = true;
      }
    });
    try {
      final next = await NguonCService.latest(page);
      if (!mounted) return;
      setState(() {
        final known = movies.map((m) => m.slug).toSet();
        movies.addAll(next.where((m) => !known.contains(m.slug)));
        if (next.isEmpty || next.length < 1) hasMore = false;
        else page++;
        if (next.isEmpty) hasMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final featured = movies.isNotEmpty ? movies.first : null;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: accentRed,
          onRefresh: () => loadMore(refresh: true),
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  child: Row(children: [
                    const Icon(Icons.play_circle_fill, color: accentRed, size: 34),
                    const SizedBox(width: 8),
                    const Text('abcfilm', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.8)),
                    const Spacer(),
                    IconButton(onPressed: () => loadMore(refresh: true), icon: const Icon(Icons.refresh)),
                  ]),
                ),
              ),
              if (featured != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: () => openMovie(context, featured),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 300,
                          child: Stack(fit: StackFit.expand, children: [
                            MovieImage(url: featured.image, fit: BoxFit.cover),
                            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xF0000000)], stops: [.25, 1]))),
                            Positioned(left: 18, right: 18, bottom: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('ĐỀ XUẤT HÔM NAY', style: TextStyle(color: accentRed, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                              const SizedBox(height: 6),
                              Text(featured.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: accentRed, foregroundColor: Colors.white),
                                onPressed: () => openMovie(context, featured),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Xem chi tiết'),
                              ),
                            ])),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(18, 24, 18, 10), child: Text('Phim mới cập nhật', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)))),
              if (error != null && movies.isEmpty)
                SliverToBoxAdapter(child: ErrorPanel(message: error!, retry: () => loadMore(refresh: true))),
              if (movies.isEmpty && loading)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: accentRed)))),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= movies.length) return const Center(child: CircularProgressIndicator(color: accentRed));
                      final movie = movies[index];
                      return MovieCard(movie: movie);
                    },
                    childCount: movies.length + (loading && movies.isNotEmpty ? 1 : 0),
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: .53,
                  ),
                ),
              ),
              if (error != null && movies.isNotEmpty)
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: Colors.white70)))),
              if (!hasMore && movies.isNotEmpty)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Đã tải hết dữ liệu API cung cấp', style: TextStyle(color: Colors.white54))))),
            ],
          ),
        ),
      ),
    );
  }
}

class MovieImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const MovieImage({super.key, required this.url, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return Container(color: panelBg, child: const Center(child: Icon(Icons.movie_outlined, size: 40, color: Colors.white30)));
    return CachedNetworkImage(
      imageUrl: url.startsWith('//') ? 'https:$url' : url,
      fit: fit,
      placeholder: (_, __) => Container(color: panelBg),
      errorWidget: (_, __, ___) => Container(color: panelBg, child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white30, size: 38))),
    );
  }
}

class MovieCard extends StatelessWidget {
  final Movie movie;
  const MovieCard({super.key, required this.movie});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openMovie(context, movie),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                MovieImage(url: movie.image),
                if (movie.quality.isNotEmpty)
                  Positioned(left: 5, top: 5, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), decoration: BoxDecoration(color: accentRed, borderRadius: BorderRadius.circular(4)), child: Text(movie.quality, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
              ]),
            ),
          ),
          const SizedBox(height: 7),
          Text(movie.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          if (movie.year.isNotEmpty) Text(movie.year, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );
}

void openMovie(BuildContext context, Movie movie) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailPage(movie: movie)));
}

class MovieDetailPage extends StatefulWidget {
  final Movie movie;
  const MovieDetailPage({super.key, required this.movie});
  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> {
  Movie? detail;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchDetail();
  }

  Future<void> fetchDetail() async {
    try {
      final result = await NguonCService.detail(widget.movie.slug);
      if (mounted) setState(() { detail = result; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString().replaceFirst('Exception: ', ''); loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = detail ?? widget.movie;
    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin phim')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: 16 / 9, child: MovieImage(url: movie.image))),
        const SizedBox(height: 18),
        Text(movie.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        if (movie.originName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(movie.originName, style: const TextStyle(color: Colors.white60))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (movie.year.isNotEmpty) _chip(movie.year),
          if (movie.quality.isNotEmpty) _chip(movie.quality),
          if (movie.currentEpisode.isNotEmpty) _chip(movie.currentEpisode),
        ]),
        const SizedBox(height: 18),
        const Text('Nội dung', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(movie.description.isEmpty ? 'Chưa có mô tả từ API.' : movie.description, style: const TextStyle(height: 1.5, color: Colors.white70)),
        const SizedBox(height: 22),
        const Text('Danh sách tập / nguồn phát', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (loading) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(color: accentRed))),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Không tải được chi tiết: $error', style: const TextStyle(color: Colors.orangeAccent))),
        ..._episodeWidgets(context, movie.episodes),
        if (!loading && movie.episodes.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 10), child: Text('API chưa trả về danh sách tập cho phim này.', style: TextStyle(color: Colors.white54))),
      ]),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: panelBg, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
    child: Text(text, style: const TextStyle(fontSize: 12)),
  );

  List<Widget> _episodeWidgets(BuildContext context, List<dynamic> episodes) {
    final widgets = <Widget>[];
    for (final server in episodes) {
      if (server is! Map) continue;
      final serverName = '${server['server_name'] ?? 'Nguồn phát'}';
      widgets.add(Padding(padding: const EdgeInsets.only(top: 12, bottom: 5), child: Text(serverName, style: const TextStyle(color: accentRed, fontWeight: FontWeight.bold))));
      final items = server['items'];
      if (items is List) {
        for (final item in items) {
          if (item is! Map) continue;
          final label = '${item['name'] ?? item['slug'] ?? 'Tập phim'}';
          final embed = '${item['embed'] ?? item['link_embed'] ?? ''}';
          final m3u8 = '${item['m3u8'] ?? item['link_m3u8'] ?? ''}';
          final direct = m3u8.isNotEmpty ? m3u8 : embed;
          if (direct.isEmpty) continue;
          widgets.add(Card(
            color: panelBg,
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: accentRed, child: Icon(Icons.play_arrow, color: Colors.white)),
              title: Text(label),
              subtitle: Text(direct.contains('.m3u8') || direct.contains('.mp4') ? 'Video trực tiếp' : 'Nguồn nhúng'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(title: '${widget.movie.name} · $label', url: direct))),
            ),
          ));
        }
      }
    }
    return widgets;
  }
}

class PlayerPage extends StatefulWidget {
  final String title;
  final String url;
  const PlayerPage({super.key, required this.title, required this.url});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? controller;
  WebViewController? webController;
  bool isDirect = false;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    final lower = widget.url.toLowerCase().split('?').first;
    isDirect = lower.endsWith('.m3u8') || lower.endsWith('.mp4');
    if (isDirect) {
      controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      controller!.initialize().then((_) {
        if (!mounted) return;
        controller!.play();
        setState(() => loading = false);
      }).catchError((Object e) {
        if (mounted) setState(() { loading = false; error = 'Không thể phát nguồn video này.'; });
      });
    } else {
      webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) { if (mounted) setState(() => loading = false); },
          onWebResourceError: (_) { if (mounted) setState(() { loading = false; error = 'Trang nhúng không tải được. Nguồn có thể chặn WebView.'; }); },
        ))
        ..loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: Column(children: [
      Expanded(
        child: Center(
          child: loading
              ? const CircularProgressIndicator(color: accentRed)
              : error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center))
                  : isDirect && controller != null
                      ? AspectRatio(aspectRatio: controller!.value.aspectRatio == 0 ? 16 / 9 : controller!.value.aspectRatio, child: VideoPlayer(controller!))
                      : webController != null
                          ? WebViewWidget(controller: webController!)
                          : const Text('Không có nguồn phát'),
        ),
      ),
      if (isDirect && controller != null && controller!.value.isInitialized)
        VideoProgressIndicator(controller!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: accentRed)),
      if (isDirect && controller != null && controller!.value.isInitialized)
        Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: () => controller!.seekTo(controller!.value.position - const Duration(seconds: 10)), icon: const Icon(Icons.replay_10)),
          IconButton(onPressed: () => setState(() => controller!.value.isPlaying ? controller!.pause() : controller!.play()), icon: Icon(controller!.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 42, color: accentRed)),
          IconButton(onPressed: () => controller!.seekTo(controller!.value.position + const Duration(seconds: 10)), icon: const Icon(Icons.forward_10)),
        ])),
      Padding(padding: const EdgeInsets.all(12), child: Text('Chỉ phát nội dung bạn có quyền xem.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54))),
    ]),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final input = TextEditingController();
  Timer? debounce;
  List<Movie> results = [];
  bool loading = false;
  String? error;

  void search(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), () async {
      if (value.trim().isEmpty) { if (mounted) setState(() { results = []; error = null; }); return; }
      setState(() { loading = true; error = null; });
      try {
        final data = await NguonCService.search(value);
        if (mounted) setState(() => results = data);
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) setState(() => loading = false);
      }
    });
  }

  @override
  void dispose() { input.dispose(); debounce?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tìm kiếm')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: TextField(
        controller: input,
        onChanged: search,
        decoration: InputDecoration(
          hintText: 'Nhập tên phim...',
          prefixIcon: const Icon(Icons.search, color: accentRed),
          filled: true,
          fillColor: panelBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      )),
      if (loading) const LinearProgressIndicator(color: accentRed),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.orangeAccent))),
      Expanded(child: results.isEmpty
        ? Center(child: Text(input.text.isEmpty ? 'Tìm phim theo tên' : loading ? 'Đang tìm...' : 'Không tìm thấy trong các trang đã kiểm tra', style: const TextStyle(color: Colors.white54)))
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: .53),
            itemBuilder: (_, i) => MovieCard(movie: results[i]),
          )),
    ]),
  );
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yêu thích')),
    body: const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Tính năng lưu yêu thích sẽ được bổ sung ở bản tiếp theo.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)))),
  );
}

class ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const ErrorPanel({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(children: [
      const Icon(Icons.cloud_off, size: 42, color: accentRed),
      const SizedBox(height: 10),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: retry, style: FilledButton.styleFrom(backgroundColor: accentRed), icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
    ]),
  );
}
