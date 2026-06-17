import 'package:PiliPlus/http/emby_source.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// Emby 自定义番剧源服务
///
/// 负责登录态维护、番剧/剧集匹配、以及把 Emby 的媒体源转换为
/// B站 [PlayUrlModel] 供现有播放器使用。
abstract final class EmbySourceService {
  static const _tag = '[EmbySource]';

  static String? _cachedAccessToken;
  static String? _cachedUserId;
  static Map<String, String>? _cachedBindings;

  static String get baseUrl => Pref.bangumiEmbyServerUrl.trim();

  static String get accessToken {
    return _cachedAccessToken ??=
        GStorage.setting.get(SettingBoxKey.bangumiEmbyAccessToken, defaultValue: '') as String;
  }

  static String get userId {
    return _cachedUserId ??=
        GStorage.setting.get(SettingBoxKey.bangumiEmbyUserId, defaultValue: '') as String;
  }

  static bool get isAuthorized => accessToken.isNotEmpty && userId.isNotEmpty;

  static bool get hasServerUrl => baseUrl.isNotEmpty;

  static Future<void> saveAuth({
    required String accessToken,
    required String userId,
  }) async {
    _cachedAccessToken = accessToken;
    _cachedUserId = userId;
    await GStorage.setting.put(SettingBoxKey.bangumiEmbyAccessToken, accessToken);
    await GStorage.setting.put(SettingBoxKey.bangumiEmbyUserId, userId);
  }

  static Future<void> clearAuth() async {
    _cachedAccessToken = null;
    _cachedUserId = null;
    await GStorage.setting.delete(SettingBoxKey.bangumiEmbyAccessToken);
    await GStorage.setting.delete(SettingBoxKey.bangumiEmbyUserId);
  }

  static Future<LoadingState<void>> login({
    required String username,
    required String password,
  }) async {
    if (baseUrl.isEmpty) {
      return const Error('Emby 服务器地址未配置');
    }
    final res = await EmbySourceHttp.authenticateByName(
      baseUrl: baseUrl,
      username: username,
      password: password,
      deviceId: _deviceId,
    );
    if (res is Error) return res;
    final data = (res as Success<Map<String, dynamic>>).response;
    final token = data['AccessToken'] as String?;
    final user = data['User'] as Map<String, dynamic>?;
    final uid = user?['Id'] as String?;
    if (token == null || token.isEmpty || uid == null || uid.isEmpty) {
      return const Error('Emby 登录返回信息不完整');
    }
    await saveAuth(accessToken: token, userId: uid);
    return const Success(null);
  }

  static String get _deviceId {
    // 用 B站账号 mid 或一个固定 id 均可，Emby 不严格要求唯一。
    return 'piliplusv_${Pref.userInfoCache?.mid ?? 'guest'}';
  }

  /// 按 B站番剧信息匹配 Emby 剧集并返回 [PlayUrlModel]。
  static Future<LoadingState<PlayUrlModel>> fetchPlayUrl({
    required int cid,
    required int episodeIndex,
    String? seriesTitle,
    String? episodeTitle,
    String? bvid,
    int? epId,
    int? seasonId,
  }) async {
    if (baseUrl.isEmpty) {
      return const Error('Emby 服务器地址未配置');
    }
    if (!isAuthorized) {
      return const Error('Emby 未登录');
    }

    _log('匹配开始 title=$seriesTitle ep=$episodeIndex epTitle=$episodeTitle');

    // 1. 用番剧标题精确搜索 Series
    String? seriesId;
    _log('步骤1：精确搜索 seriesTitle=$seriesTitle');
    if (seriesTitle != null && seriesTitle.isNotEmpty) {
      final exact = await _searchSeriesExact(seriesTitle);
      if (exact != null) seriesId = exact;

      // 2. 清洗后模糊搜索
      if (seriesId == null) {
        final fuzzyList = _fuzzyTitles(seriesTitle);
        _log('步骤2：模糊搜索 variants=$fuzzyList');
        for (final t in fuzzyList) {
          final fuzzy = await _searchSeriesBest(t);
          if (fuzzy != null) {
            seriesId = fuzzy;
            _log('模糊命中 seriesId=$seriesId variant=$t');
            break;
          }
        }
      }
      if (seriesId != null) {
        _log('精确命中 seriesId=$seriesId');
      }
    }

    // 3. 用集标题反查 Episode
    String? episodeId;
    if (seriesId == null && episodeTitle != null && episodeTitle.isNotEmpty) {
      _log('步骤3：按集标题反查 episodeTitle=$episodeTitle');
      final ep = await _searchEpisodeBest(episodeTitle, episodeIndex);
      if (ep != null) {
        seriesId = ep.seriesId;
        episodeId = ep.id;
      }
    }

    // 4. 手动绑定缓存兜底
    if (seriesId == null && seasonId != null) {
      final cached = _getCachedBinding(seasonId.toString());
      _log('步骤4：手动绑定缓存 cached=$cached');
      if (cached != null) {
        _log('使用手动绑定缓存 seasonId=$seasonId -> seriesId=$cached');
        seriesId = cached;
      }
    }

    if (seriesId == null) {
      _log('匹配失败：未在 Emby 找到对应番剧');
      return const Error('未在 Emby 找到对应番剧');
    }

    // 找到对应 Episode。优先标题反查，再按集号兜底。
    _log('步骤5：查找集 expectedIndex=$episodeIndex seriesId=$seriesId');
    episodeId ??= await _findEpisodeId(
      seriesId: seriesId,
      expectedIndex: episodeIndex,
      title: episodeTitle,
    );
    if (episodeId == null) {
      _log('匹配失败：未在 Emby 找到第 $episodeIndex 集');
      return Error('未在 Emby 找到第 $episodeIndex 集');
    }
    _log('匹配成功 episodeId=$episodeId');

    // 取 PlaybackInfo
    final playbackRes = await EmbySourceHttp.getPlaybackInfo(
      baseUrl: baseUrl,
      accessToken: accessToken,
      userId: userId,
      itemId: episodeId,
    );
    if (playbackRes is Error) return playbackRes;
    final playbackData = (playbackRes as Success<Map<String, dynamic>>).response;

    return _buildPlayUrlModel(playbackData, episodeId);
  }

  static Future<String?> _searchSeriesExact(String title) async {
    final res = await EmbySourceHttp.searchSeries(
      baseUrl: baseUrl,
      accessToken: accessToken,
      userId: userId,
      searchTerm: title,
      libraryId: _libraryId,
      limit: 10,
    );
    if (res is Error) return null;
    final items = (res as Success<List<Map<String, dynamic>>>).response;
    final target = _normalize(title);
    for (final item in items) {
      final name = item['Name'] as String?;
      if (_normalize(name) == target) {
        return item['Id'] as String?;
      }
    }
    return null;
  }

  static Future<String?> _searchSeriesBest(String title) async {
    final res = await EmbySourceHttp.searchSeries(
      baseUrl: baseUrl,
      accessToken: accessToken,
      userId: userId,
      searchTerm: title,
      libraryId: _libraryId,
      limit: 20,
    );
    if (res is Error) return null;
    final items = (res as Success<List<Map<String, dynamic>>>).response;
    if (items.isEmpty) return null;
    final target = _normalize(title);
    String? bestId;
    double bestScore = 0.0;
    const threshold = 0.6;
    for (final item in items) {
      final name = item['Name'] as String? ?? '';
      final score = _titleSimilarity(_normalize(name), target);
      if (score > bestScore) {
        bestScore = score;
        bestId = item['Id'] as String?;
      }
    }
    if (bestScore < threshold) {
      _log('模糊匹配最佳分数 $bestScore 低于阈值 $threshold，放弃');
      return null;
    }
    return bestId;
  }

  static Future<_EmbyEpisodeMatch?> _searchEpisodeBest(
    String title,
    int expectedIndex,
  ) async {
    final res = await EmbySourceHttp.searchEpisodes(
      baseUrl: baseUrl,
      accessToken: accessToken,
      userId: userId,
      searchTerm: title,
      libraryId: _libraryId,
      limit: 30,
    );
    if (res is Error) return null;
    final items = (res as Success<List<Map<String, dynamic>>>).response;
    _EmbyEpisodeMatch? best;
    double bestScore = 0.0;
    const titleThreshold = 0.55;
    final target = _normalize(title);
    for (final item in items) {
      final idx = _parseIndexNumber(item['IndexNumber']);
      final itemName = item['Name'] as String? ?? '';
      final itemSeriesName = item['SeriesName'] as String? ?? '';
      final score = _max(
        _titleSimilarity(_normalize(itemName), target),
        _titleSimilarity(_normalize(itemSeriesName), target),
      );
      // 集号一致时优先，否则取标题最像的。
      if (idx != null && idx == expectedIndex) {
        return _EmbyEpisodeMatch(
          id: item['Id'] as String? ?? '',
          seriesId: item['SeriesId'] as String? ?? '',
          seasonId: item['SeasonId'] as String? ?? '',
          indexNumber: idx,
        );
      }
      if (score > bestScore && score >= titleThreshold) {
        bestScore = score;
        best = _EmbyEpisodeMatch(
          id: item['Id'] as String? ?? '',
          seriesId: item['SeriesId'] as String? ?? '',
          seasonId: item['SeasonId'] as String? ?? '',
          indexNumber: idx ?? expectedIndex,
        );
      }
    }
    return best;
  }

  static Future<String?> _findEpisodeId({
    required String seriesId,
    required int expectedIndex,
    String? title,
  }) async {
    // 先尝试取 Series 下的 Seasons，再取 Season 下的 Episodes
    final seasonsRes = await EmbySourceHttp.listItems(
      baseUrl: baseUrl,
      accessToken: accessToken,
      userId: userId,
      parentId: seriesId,
      includeItemTypes: 'Season',
      limit: 50,
    );
    List<String> seasonIds = [];
    if (seasonsRes is Success<List<Map<String, dynamic>>>) {
      seasonIds = seasonsRes.response
          .map((e) => e['Id'] as String?)
          .whereType<String>()
          .toList();
    }
    if (seasonIds.isEmpty) seasonIds = [seriesId];

    String? fallbackByIndex;
    _EmbyEpisodeMatch? fallbackByTitle;
    for (final seasonId in seasonIds) {
      final epsRes = await EmbySourceHttp.listItems(
        baseUrl: baseUrl,
        accessToken: accessToken,
        userId: userId,
        parentId: seasonId,
        includeItemTypes: 'Episode',
        fields: 'IndexNumber',
        limit: 1000,
      );
      if (epsRes is Error) continue;
      final episodes = (epsRes as Success<List<Map<String, dynamic>>>).response;
      for (final ep in episodes) {
        final idx = _parseIndexNumber(ep['IndexNumber']);
        final epName = ep['Name'] as String? ?? '';
        // 集号一致优先
        if (idx == expectedIndex) {
          return ep['Id'] as String?;
        }
        // 标题一致作为次优先
        if (title != null && title.isNotEmpty) {
          final score = _titleSimilarity(_normalize(epName), _normalize(title));
          if (score >= 0.8 &&
              (fallbackByTitle == null || score > fallbackByTitle.score)) {
            fallbackByTitle = _EmbyEpisodeMatch(
              id: ep['Id'] as String? ?? '',
              seriesId: seriesId,
              seasonId: seasonId,
              indexNumber: idx ?? expectedIndex,
              score: score,
            );
          }
        }
        // 兜底：记录最后一个按顺序的 episode，避免空结果
        if (fallbackByIndex == null && idx != null) {
          fallbackByIndex = ep['Id'] as String?;
        }
      }
    }
    return fallbackByTitle?.id ?? fallbackByIndex;
  }

  static LoadingState<PlayUrlModel> _buildPlayUrlModel(
    Map<String, dynamic> playbackData,
    String itemId,
  ) {
    final mediaSources = playbackData['MediaSources'];
    if (mediaSources is! List || mediaSources.isEmpty) {
      return const Error('Emby 没有可用的媒体源');
    }
    final source = mediaSources.firstWhere(
      (s) => s is Map<String, dynamic> && (s['SupportsDirectStream'] == true),
      orElse: () => mediaSources.first,
    ) as Map<String, dynamic>;

    String? streamUrl;
    if (source['SupportsDirectStream'] == true) {
      streamUrl = source['DirectStreamUrl'] as String?;
      if (streamUrl == null || streamUrl.isEmpty) {
        streamUrl = _directStreamUrl(itemId);
      }
    }
    if (streamUrl == null || streamUrl.isEmpty) {
      streamUrl = source['TranscodingUrl'] as String?;
    }
    if (streamUrl == null || streamUrl.isEmpty) {
      streamUrl = source['Path'] as String?;
    }
    if (streamUrl == null || streamUrl.isEmpty) {
      return const Error('Emby 没有可用的播放地址');
    }

    final runTimeTicks = source['RunTimeTicks'];
    final durationMs = runTimeTicks is int ? runTimeTicks ~/ 10000 : 0;
    final size = source['Size'] is int ? source['Size'] as int : 0;
    final container = source['Container'] as String? ?? 'mp4';
    _log('播放地址 streamUrl=$streamUrl container=$container');

    // 合并相对 URL 并追加 api_key 鉴权参数
    streamUrl = _resolveEmbyUrl(streamUrl);

    // 对 HLS/TS 容器统一返回 mp4 容器名，避免播放器层解析异常。
    final format = _isHlsContainer(container) ? 'mp4' : container;

    // Emby fallback 为单一原画流，不暴露画质切换；播放器进度恢复由 defaultST 控制，
    // 不通过 durl seek 参数透传给 Emby URL。
    const quality = 80;
    final model = PlayUrlModel(
      from: 'emby',
      result: 'suee',
      quality: quality,
      format: format,
      timeLength: durationMs,
      acceptFormat: format,
      acceptDesc: const ['原画'],
      acceptQuality: const [quality],
      videoCodecid: 0,
      seekParam: '',
      seekType: '',
    );
    model.durl = [
      Durl(
        order: 1,
        length: durationMs,
        size: size,
        url: streamUrl,
        backupUrl: const [],
      ),
    ];
    return Success(model);
  }

  static bool _isHlsContainer(String container) {
    final c = container.toLowerCase();
    return c == 'm3u8' || c == 'ts' || c == 'hls';
  }

  static String _resolveEmbyUrl(String rawUrl) {
    final base = Uri.parse(baseUrl);
    final resolved = rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
        ? Uri.parse(rawUrl)
        : base.resolve(rawUrl);
    // Emby 与 Jellyfin 通用 api_key 鉴权参数
    return resolved.replace(
      queryParameters: {
        ...resolved.queryParameters,
        'api_key': accessToken,
      },
    ).toString();
  }

  static String _directStreamUrl(String itemId) {
    final base = Uri.parse(baseUrl);
    return base
        .replace(
          path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/emby/Videos/$itemId/stream',
          queryParameters: {
            'static': 'true',
            'MediaSourceId': itemId,
          },
        )
        .toString();
  }

  static String? get _libraryId {
    final id = Pref.bangumiEmbyLibraryId.trim();
    return id.isEmpty ? null : id;
  }

  static List<String> _fuzzyTitles(String title) {
    String normalized = _normalize(title);
    final variants = <String>{normalized};

    // 去掉常见地域/语言/字幕标注
    normalized = normalized
        .replaceAllMapped(
          RegExp(r'\s*[(（【［\[][^)）】］\]]*(僅限|仅限|普通话|国语|日语|中配|繁中|简中|台灣|港澳|大陆|地区)[^)）】］\]]*[)）】］\]]?'),
          (m) => '',
        )
        .trim();
    if (normalized.isNotEmpty) variants.add(normalized);

    // 替换季/期/部/Part 数字变体为不带后缀的标题
    final seasonless = normalized
        .replaceAllMapped(
          RegExp(r'[\s\-_]?(第?\s*\d+\s*[季期部]|[Ss]eason\s*\d+|\b\d+[Nn][Dd]\s*[Ss]eason|\b[Pp]art\s*\d+|\b\d+\s*期)$'),
          (m) => '',
        )
        .trim();
    if (seasonless.isNotEmpty && seasonless != normalized) {
      variants.add(seasonless);
    }

    // 去掉冒号/全角冒号副标题
    final colonIdx = normalized.indexOf(RegExp(r'[:：]'));
    if (colonIdx > 0) {
      variants.add(normalized.substring(0, colonIdx).trim());
    }
    final colonIdx2 = seasonless.indexOf(RegExp(r'[:：]'));
    if (colonIdx2 > 0 && colonIdx2 != colonIdx) {
      variants.add(seasonless.substring(0, colonIdx2).trim());
    }

    return variants.where((e) => e.isNotEmpty).toList();
  }

  static String _normalize(String? value) {
    if (value == null) return '';
    return value
        .replaceAll(RegExp(r'[【】\(\)（）\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static int? _parseIndexNumber(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double _titleSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.9;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - dist / maxLen;
  }

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = _min(
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        );
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }

  static int _min(int a, int b, int c) => (a < b ? a : b) < c ? (a < b ? a : b) : c;

  static double _max(double a, double b) => a > b ? a : b;

  static String? _getCachedBinding(String seasonId) {
    final bindings = _loadBindings();
    return bindings[seasonId];
  }

  static Future<void> cacheBinding(String seasonId, String embySeriesId) async {
    final bindings = _loadBindings();
    bindings[seasonId] = embySeriesId;
    await _saveBindings(bindings);
  }

  static Future<void> clearBinding(String seasonId) async {
    final bindings = _loadBindings();
    if (bindings.remove(seasonId) != null) {
      await _saveBindings(bindings);
    }
  }

  /// 供设置页清除缓存后让内存缓存失效。
  static void clearBindingsCache() {
    _cachedBindings = null;
  }

  static Map<String, String> _loadBindings() {
    if (_cachedBindings != null) return _cachedBindings!;
    final raw = GStorage.setting.get(
      SettingBoxKey.bangumiEmbyBindings,
      defaultValue: <String, String>{},
    );
    if (raw is Map) {
      _cachedBindings = Map<String, String>.fromEntries(
        raw.entries
            .where((e) => e.key is String && e.value is String)
            .map((e) => MapEntry(e.key as String, e.value as String)),
      );
    } else {
      _cachedBindings = <String, String>{};
    }
    return _cachedBindings!;
  }

  static Future<void> _saveBindings(Map<String, String> bindings) async {
    _cachedBindings = bindings;
    await GStorage.setting.put(SettingBoxKey.bangumiEmbyBindings, bindings);
  }

  static void _log(String message) {
    logger.i('$_tag $message');
  }
}

class _EmbyEpisodeMatch {
  final String id;
  final String seriesId;
  final String seasonId;
  final int indexNumber;
  final double score;

  _EmbyEpisodeMatch({
    required this.id,
    required this.seriesId,
    required this.seasonId,
    required this.indexNumber,
    this.score = 0.0,
  });
}
