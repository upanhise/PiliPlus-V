import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models/common/bangumi_source_policy.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/services/account_service.dart';
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

  static BangumiSourcePolicy resolveInitialPolicy(VipState vipState) {
    return switch (vipState) {
      VipState.vip => BangumiSourcePolicy.official,
      VipState.nonVip || VipState.notLogin || VipState.unknown =>
        BangumiSourcePolicy.official,
    };
  }

  static bool get enableCustomSource => Pref.enableBangumiCustomSource;

  static String get customSourceUrl => Pref.bangumiCustomSourceUrl.trim();

  static bool get showBangumiSourceToast => Pref.showBangumiSourceToast;

  static bool get tryCustomSourceOnOfficialFailure =>
      Pref.tryBangumiCustomSourceOnOfficialFailure;

  static bool get hasCustomSourceConfigured =>
      enableCustomSource && customSourceUrl.isNotEmpty;

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
  }) async {
    _log(
      'selectedPolicy=${BangumiSourcePolicy.fallback.name} '
      'epId=$epId seasonId=$seasonId cid=$cid bvid=$bvid',
    );
    if (!enableCustomSource) {
      _log('fallbackPlayUrl disabled by setting');
      return const Error('自定义番剧源未启用');
    }
    if (customSourceUrl.isEmpty) {
      _log('fallbackPlayUrl missing custom source url');
      return const Error('自定义番剧源地址未配置');
    }
    _log(
      'fallbackPlayUrl placeholder url=$customSourceUrl epId=$epId seasonId=$seasonId cid=$cid bvid=$bvid',
    );
    return const Error('当前版本仅提供自定义番剧源配置骨架，尚未接入实际源实现');
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
