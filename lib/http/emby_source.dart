import 'dart:convert' show jsonEncode;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:dio/dio.dart';

/// Emby 自定义番剧源 API 封装
///
/// 仅负责原始 HTTP 请求与简单的 code 判断，业务层匹配逻辑在
/// [EmbySourceService]。
abstract final class EmbySourceHttp {
  static Map<String, String> _authHeaders({
    String? accessToken,
    String? client,
    String? device,
    String? deviceId,
    String? version,
  }) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-Emby-Authorization':
        'MediaBrowser '
        'Client="${client ?? 'PiliPlusV'}", '
        'Device="${device ?? 'Android'}", '
        'DeviceId="${deviceId ?? 'piliplusv'}", '
        'Version="${version ?? '2.0.9'}"',
    if (accessToken != null && accessToken.isNotEmpty)
      'X-Emby-Token': accessToken,
  };

  static String _apiUrl(String baseUrl, String path, String? userId) {
    final uri = Uri.parse(baseUrl);
    final query = <String, String>{};
    if (userId != null && userId.isNotEmpty) {
      query['UserId'] = userId;
    }
    return uri.replace(
      path: '${uri.path.replaceAll(RegExp(r'/+$'), '')}/$path',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 用户名密码登录，返回 AccessToken 与 UserId。
  static Future<LoadingState<Map<String, dynamic>>> authenticateByName({
    required String baseUrl,
    required String username,
    required String password,
    String? deviceId,
  }) async {
    final url = _apiUrl(baseUrl, 'emby/Users/AuthenticateByName', null);
    try {
      final res = await Request().post(
        url,
        data: jsonEncode({'Username': username, 'Pw': password}),
        options: Options(
          responseType: ResponseType.json,
          headers: _authHeaders(deviceId: deviceId),
        ),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return const Error('Emby 登录返回格式异常');
      }
      if (data['AccessToken'] is! String ||
          (data['AccessToken'] as String).isEmpty) {
        return Error(data['errorMessage']?.toString() ?? 'Emby 登录失败');
      }
      return Success(data);
    } on DioException catch (e) {
      return Error('Emby 登录请求失败: ${e.message}');
    } catch (e) {
      return Error('Emby 登录异常: $e');
    }
  }

  /// 搜索 Series（电视剧/番剧）。
  static Future<LoadingState<List<Map<String, dynamic>>>> searchSeries({
    required String baseUrl,
    required String accessToken,
    required String userId,
    required String searchTerm,
    String? libraryId,
    int limit = 20,
  }) => _searchItems(
    baseUrl: baseUrl,
    accessToken: accessToken,
    userId: userId,
    searchTerm: searchTerm,
    includeItemTypes: 'Series',
    parentId: libraryId,
    limit: limit,
  );

  /// 搜索 Episode（单集）。
  static Future<LoadingState<List<Map<String, dynamic>>>> searchEpisodes({
    required String baseUrl,
    required String accessToken,
    required String userId,
    required String searchTerm,
    String? libraryId,
    int limit = 20,
  }) => _searchItems(
    baseUrl: baseUrl,
    accessToken: accessToken,
    userId: userId,
    searchTerm: searchTerm,
    includeItemTypes: 'Episode',
    parentId: libraryId,
    limit: limit,
    fields: 'IndexNumber,SeriesId,SeasonId',
  );

  /// 列出 parentId 下的 Items。
  static Future<LoadingState<List<Map<String, dynamic>>>> listItems({
    required String baseUrl,
    required String accessToken,
    required String userId,
    required String parentId,
    required String includeItemTypes,
    String? fields,
    int limit = 1000,
  }) async {
    final query = <String, String>{
      'ParentId': parentId,
      'IncludeItemTypes': includeItemTypes,
      'Recursive': 'false',
      'Limit': limit.toString(),
      if (fields != null && fields.isNotEmpty) 'Fields': fields,
    };
    final url = Uri.parse(_apiUrl(baseUrl, 'emby/Items', userId))
        .replace(queryParameters: query)
        .toString();
    return _getItems(url, accessToken);
  }

  /// 通用搜索。
  static Future<LoadingState<List<Map<String, dynamic>>>> _searchItems({
    required String baseUrl,
    required String accessToken,
    required String userId,
    required String searchTerm,
    required String includeItemTypes,
    String? parentId,
    String? fields,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'SearchTerm': searchTerm,
      'IncludeItemTypes': includeItemTypes,
      'Recursive': 'true',
      'Limit': limit.toString(),
      if (parentId != null && parentId.isNotEmpty) 'ParentId': parentId,
      if (fields != null && fields.isNotEmpty) 'Fields': fields,
    };
    final url = Uri.parse(_apiUrl(baseUrl, 'emby/Items', userId))
        .replace(queryParameters: query)
        .toString();
    return _getItems(url, accessToken);
  }

  static Future<LoadingState<List<Map<String, dynamic>>>> _getItems(
    String url,
    String accessToken,
  ) async {
    try {
      final res = await Request().get(
        url,
        options: Options(
          responseType: ResponseType.json,
          headers: _authHeaders(accessToken: accessToken),
        ),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return const Error('Emby 返回格式异常');
      }
      final items = data['Items'];
      if (items is! List) {
        return const Error('Emby 返回缺少 Items');
      }
      return Success(
        items.whereType<Map<String, dynamic>>().toList(),
      );
    } on DioException catch (e) {
      return Error('Emby 请求失败: ${e.message}');
    } catch (e) {
      return Error('Emby 请求异常: $e');
    }
  }

  /// 获取剧集可播放的媒体源。
  static Future<LoadingState<Map<String, dynamic>>> getPlaybackInfo({
    required String baseUrl,
    required String accessToken,
    required String userId,
    required String itemId,
    bool forceDirectStream = true,
  }) async {
    final url = Uri.parse(
      _apiUrl(baseUrl, 'emby/Items/$itemId/PlaybackInfo', userId),
    ).replace(queryParameters: {}).toString();
    try {
      final res = await Request().post(
        url,
        data: jsonEncode({
          'UserId': userId,
          'MaxStreamingBitrate': 140000000,
          'MaxStaticBitrate': 140000000,
          'MusicStreamingTranscodingBitrate': 192000,
          'SubtitleStreamIndex': null,
          'AudioStreamIndex': null,
          'MediaSourceId': itemId,
          'DeviceProfile': {
            'Container': 'mp4,mkv,webm',
            'Type': 'Video',
            'VideoCodec': 'h264,hevc,av1,vp8,vp9',
            'AudioCodec': 'aac,mp3,opus,flac,ac3,eac3',
            'MaxAudioChannels': '6',
            'DirectPlayProfiles': [
              {
                'Container': 'mp4,mkv,webm',
                'Type': 'Video',
                'VideoCodec': 'h264,hevc,av1,vp8,vp9',
                'AudioCodec': 'aac,mp3,opus,flac,ac3,eac3',
              }
            ],
            'TranscodingProfiles': [
              {
                'Container': 'ts',
                'Type': 'Video',
                'VideoCodec': 'h264',
                'AudioCodec': 'aac',
                'Protocol': 'hls',
              }
            ],
          }
        }),
        options: Options(
          responseType: ResponseType.json,
          headers: _authHeaders(accessToken: accessToken),
        ),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return const Error('Emby PlaybackInfo 返回格式异常');
      }
      final errorCode = data['ErrorCode'];
      if (errorCode != null) {
        return Error(data['ErrorMessage']?.toString() ?? 'Emby 播放信息错误');
      }
      return Success(data);
    } on DioException catch (e) {
      return Error('Emby PlaybackInfo 请求失败: ${e.message}');
    } catch (e) {
      return Error('Emby PlaybackInfo 异常: $e');
    }
  }
}
