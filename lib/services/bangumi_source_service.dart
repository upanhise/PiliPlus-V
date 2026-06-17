import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models/common/bangumi_source_policy.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/services/emby_source_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:get/get.dart';

abstract final class BangumiSourceService {
  static const _tag = '[BangumiPlay]';
  static DateTime? _lastVipRefreshAt;

  static VipState get vipState {
    try {
      return Get.find<AccountService>().vipState;
    } catch (e) {
      _log('vipState unknown: $e');
      return VipState.unknown;
    }
  }

  static Future<VipState> refreshVipState() async {
    late final AccountService accountService;
    try {
      accountService = Get.find<AccountService>();
    } catch (e) {
      _log('refreshVipState account service missing: $e');
      return VipState.unknown;
    }

    if (!accountService.isLogin.value) {
      return VipState.notLogin;
    }

    final now = DateTime.now();
    if (_lastVipRefreshAt != null &&
        now.difference(_lastVipRefreshAt!) < const Duration(minutes: 5)) {
      return accountService.vipState;
    }
    _lastVipRefreshAt = now;

    try {
      final result = await UserHttp.userInfo();
      if (result case Success(:final response)) {
        if (response.isLogin != true) {
          accountService
            ..face.value = ''
            ..isLogin.value = false;
          await GStorage.userInfo.delete('userInfoCache');
          return VipState.notLogin;
        }

        accountService.face.value = response.face ?? '';
        if (!accountService.isLogin.value) {
          accountService.isLogin.value = true;
        }
        if (response != Pref.userInfoCache) {
          await GStorage.userInfo.put('userInfoCache', response);
        }
        return accountService.vipState;
      }
      _log('refreshVipState failed: $result');
      return accountService.vipState;
    } catch (e) {
      _log('refreshVipState exception: $e');
      return accountService.vipState;
    }
  }

  static BangumiSourcePolicy resolveInitialPolicy({
    required VipState vipState,
  }) {
    // 非会员用户若开启偏好，可直接走自定义源，跳过 B站官方试看。
    if (vipState != VipState.vip &&
        preferCustomSourceForNonVip &&
        hasCustomSourceConfigured) {
      _log('prefer custom source for non-vip');
      return BangumiSourcePolicy.fallback;
    }
    return BangumiSourcePolicy.official;
  }

  static bool get enableCustomSource => Pref.enableBangumiCustomSource;

  static bool get showBangumiSourceToast => Pref.showBangumiSourceToast;

  static bool get tryCustomSourceOnOfficialFailure =>
      Pref.tryBangumiCustomSourceOnOfficialFailure;

  static bool get preferCustomSourceForNonVip =>
      Pref.preferCustomSourceForNonVip;

  static bool get hasCustomSourceConfigured =>
      enableCustomSource && EmbySourceService.hasServerUrl;

  static bool shouldTryFallback({
    required VipState vipState,
    required LoadingState<PlayUrlModel> officialResult,
  }) {
    // 大会员无需 fallback；未知状态保守处理（无法确认身份则不降级）
    if (vipState == VipState.vip || vipState == VipState.unknown) {
      return false;
    }
    if (!tryCustomSourceOnOfficialFailure) {
      return false;
    }
    return officialResult is Error && _isOfficialPermissionError(officialResult);
  }

  static Future<LoadingState<PlayUrlModel>> fallbackPlayUrl({
    required int cid,
    String? bvid,
    int? epId,
    int? seasonId,
    String? seriesTitle,
    String? episodeTitle,
    int? episodeIndex,
  }) async {
    _log(
      'selectedPolicy=${BangumiSourcePolicy.fallback.name} '
      'epId=$epId seasonId=$seasonId cid=$cid bvid=$bvid',
    );
    if (!enableCustomSource) {
      _log('fallbackPlayUrl disabled by setting');
      return const Error('自定义番剧源未启用');
    }
    if (!EmbySourceService.hasServerUrl) {
      _log('fallbackPlayUrl missing Emby server url');
      return const Error('未配置 Emby 服务器，请在设置中添加');
    }

    return EmbySourceService.fetchPlayUrl(
      cid: cid,
      episodeIndex: episodeIndex ?? 1,
      seriesTitle: seriesTitle,
      episodeTitle: episodeTitle,
      bvid: bvid,
      epId: epId,
      seasonId: seasonId,
    );
  }

  static bool _isOfficialPermissionError(Error error) {
    final msg = error.errMsg ?? '';
    return msg.contains('大会员') ||
        msg.contains('会员') ||
        msg.contains('试看') ||
        msg.contains('权限') ||
        msg.contains('专属') ||
        msg.contains('付费') ||
        msg.contains('购买') ||
        // B站播放接口常见权限错误码：大会员专属/付费内容不可播放。
        error.code == 87007 ||
        error.code == 87008;
  }

  static void logDecision({
    required int cid,
    String? bvid,
    int? epId,
    int? seasonId,
    required VipState vipState,
    required BangumiSourcePolicy policy,
  }) {
    _log(
      'cid=$cid bvid=$bvid epId=$epId seasonId=$seasonId '
      'vipState=${vipState.name} selectedPolicy=${policy.name}',
    );
  }

  static void logOfficialResult(LoadingState<PlayUrlModel> result) {
    if (result is Success<PlayUrlModel>) {
      _log('officialPlayUrl success');
    } else if (result is Error) {
      _log('officialPlayUrl failed: ${result.errMsg ?? result.code}');
    }
  }

  static void logFallbackResult(LoadingState<PlayUrlModel> result) {
    if (result is Success<PlayUrlModel>) {
      _log('fallbackPlayUrl success');
    } else if (result is Error) {
      _log('fallbackPlayUrl failed: ${result.errMsg ?? result.code}');
    }
  }

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('$_tag $message');
    }
  }
}
