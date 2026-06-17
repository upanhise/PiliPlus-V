import 'package:PiliPlus/http/emby_source.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Emby 自定义番剧源服务
///
/// 负责登录态维护、番剧/剧集匹配、以及把 Emby 的媒体源转换为
/// B站 [PlayUrlModel] 供现有播放器使用。
abstract final class EmbySourceService {
  static const _tag = '[EmbySource]';

  static String? _cachedAccessToken;
  static String? _cachedUserId;

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

    _log('匹配开始 title=$seriesTitle ep=$episodeIndex');

    // 1. 用番剧标题精确搜索 Series
    String? seriesId;
    if (seriesTitle != null && seriesTitle.isNotEmpty) {
      final exact = await _searchSeriesExact(seriesTitle);
      if (exact != null) seriesId = exact;

      // 2. 清洗后模糊搜索
      if (seriesId == null) {
        for (final t in _fuzzyTitles(seriesTitle)) {
          final fuzzy = await _searchSeriesBest(t);
          if (fuzzy != null) {
            seriesId = fuzzy;
            break;
          }
        }
      }
    }

    // 3. 用集标题反查 Episode
    String? episodeId;
    if (seriesId == null && episodeTitle != null && episodeTitle.isNotEmpty) {
      final ep = await _searchEpisodeBest(episodeTitle, episodeIndex);
      if (ep != null) {
        seriesId = ep.seriesId;
        episodeId = ep.id;
      }
    }

    // 4. 手动绑定缓存兜底
    if (seriesId == null && seasonId != null) {
      final cached = _getCachedBinding(seasonId.toString());
      if (cached != null) seriesId = cached;
    }

    if (seriesId == null) {
      return const Error('未在 Emby 找到对应番剧');
    }

    // 找到对应 Episode
    episodeId ??= await _findEpisodeIdByIndex(seriesId, episodeIndex);
    if (episodeId == null) {
      return Error('未在 Emby 找到第 $episodeIndex 集');
    }

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
    for (final item in items) {
      if (_normalize(item['Name']) == _normalize(title)) {
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
    return items.first['Id'] as String?;
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
      limit: 20,
    );
    if (res is Error) return null;
    final items = (res as Success<List<Map<String, dynamic>>>).response;
    for (final item in items) {
      final idx = _parseIndexNumber(item['IndexNumber']);
      if (idx != null && idx == expectedIndex) {
        return _EmbyEpisodeMatch(
          id: item['Id'] as String? ?? '',
          seriesId: item['SeriesId'] as String? ?? '',
          seasonId: item['SeasonId'] as String? ?? '',
          indexNumber: idx,
        );
      }
    }
    return null;
  }

  static Future<String?> _findEpisodeIdByIndex(
    String seriesId,
    int episodeIndex,
  ) async {
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

    // 如果 Series 下没有 Season，直接把 Series 当 ParentId 查 Episodes
    if (seasonIds.isEmpty) seasonIds = [seriesId];

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
        if (idx == episodeIndex) {
          return ep['Id'] as String?;
        }
      }
    }
    return null;
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
      return const Error('Emby 没有可用的播放地址');
    }

    // 补齐协议与 host
    if (streamUrl.startsWith('/')) {
      final uri = Uri.parse(baseUrl);
      streamUrl = uri.replace(path: streamUrl).toString();
    }

    final runTimeTicks = source['RunTimeTicks'];
    final durationMs = runTimeTicks is int ? runTimeTicks ~/ 10000 : 0;
    final size = source['Size'] is int ? source['Size'] as int : 0;
    final container = source['Container'] as String? ?? 'mp4';

    final model = PlayUrlModel(
      from: 'emby',
      result: 'suee',
      quality: 80,
      format: container == 'm3u8' || container == 'ts' ? 'mp4' : container,
      timeLength: durationMs,
      acceptFormat: container == 'm3u8' || container == 'ts' ? 'mp4' : container,
      acceptDesc: const ['原画'],
      acceptQuality: const [80],
      videoCodecid: 7,
      seekParam: 'start',
      seekType: 'second',
      durl: [
        Durl(
          order: 1,
          length: durationMs,
          size: size,
          url: streamUrl,
          backupUrl: [],
        ),
      ],
    );
    return Success(model);
  }

  static String _directStreamUrl(String itemId) {
    final uri = Uri.parse(baseUrl);
    return uri
        .replace(
          path: '${uri.path.replaceAll(RegExp(r'/+$'), '')}/emby/Videos/$itemId/stream',
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
    final normalized = _normalize(title);
    final variants = <String>{normalized};

    final suffixes = [
      ' 第二季', ' 第2季', ' 2期', ' 第二部', ' part 2',
      ' 第三季', ' 第3季', ' 3期', ' 第三部', ' part 3',
      ' 第四季', ' 第4季', ' 4期', ' part 4',
      ' 第五季', ' 第5季', ' 5期', ' part 5',
      '（僅限台灣地區）', '（僅限港澳地區）', '（僅限中國大陸）',
      ' 普通话版', ' 国语版', ' 日语版', ' 中配版', ' 繁中版', ' 简中版',
    ];
    for (final suffix in suffixes) {
      if (normalized.toLowerCase().contains(suffix)) {
        variants.add(normalized.replaceFirst(suffix, '').trim());
      }
    }

    // 去掉冒号/全角冒号副标题
    final colonIdx = normalized.indexOf(RegExp(r'[:：]'));
    if (colonIdx > 0) {
      variants.add(normalized.substring(0, colonIdx).trim());
    }

    return variants.toList();
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

  static String? _getCachedBinding(String seasonId) {
    final raw = GStorage.setting.get(
      'bangumiEmbyBinding_$seasonId',
      defaultValue: '',
    ) as String;
    return raw.isEmpty ? null : raw;
  }

  static Future<void> cacheBinding(String seasonId, String embySeriesId) async {
    await GStorage.setting.put('bangumiEmbyBinding_$seasonId', embySeriesId);
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('$_tag $message');
  }
}

class _EmbyEpisodeMatch {
  final String id;
  final String seriesId;
  final String seasonId;
  final int indexNumber;

  _EmbyEpisodeMatch({
    required this.id,
    required this.seriesId,
    required this.seasonId,
    required this.indexNumber,
  });
}
