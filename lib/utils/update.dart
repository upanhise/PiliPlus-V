import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class Update {
  // 检查更新
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (kDebugMode) return;
    SmartDialog.dismiss();
    try {
      final res = await Request().get(
        Api.latestApp,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          extra: {'account': const NoAccount()},
        ),
      );
      if (res.data is Map || res.data.isEmpty) {
        if (!isAuto) {
          SmartDialog.showToast('检查更新失败，GitHub接口未返回数据，请检查网络');
        }
        return;
      }
      final data = res.data[0];
      final tagName = '${data['tag_name']}';
      if (isAuto && Pref.ignoredUpdateVersion == tagName) {
        return;
      }
      final int latest =
          DateTime.parse(data['created_at']).millisecondsSinceEpoch ~/ 1000;
      final bool hasUpdate = _hasUpdate(
        currentVersion: BuildConfig.versionName,
        latestVersion: tagName,
        latestBuildTime: latest,
        assets: data['assets'],
      );
      if (!hasUpdate) {
        if (!isAuto) {
          SmartDialog.showToast('已是最新版本');
        }
      } else {
        SmartDialog.show(
          animationType: SmartAnimationType.centerFade_otherSlide,
          builder: (context) {
            final colorScheme = ColorScheme.of(context);
            Widget downloadBtn(String text, {String? ext}) => TextButton(
              onPressed: () => onDownload(data, ext: ext),
              child: Text(text),
            );
            return AlertDialog(
              title: const Text('🎉 发现新版本 '),
              content: SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['tag_name']}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text('${data['body']}'),
                      TextButton(
                        onPressed: () => PageUtils.launchURL(
                          '${Constants.sourceCodeUrl}/commits/main',
                        ),
                        child: Text(
                          "点此查看完整更新(即commit)内容",
                          style: TextStyle(color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isAuto)
                  TextButton(
                    onPressed: () {
                      SmartDialog.dismiss();
                      GStorage.setting.put(
                        SettingBoxKey.ignoredUpdateVersion,
                        tagName,
                      );
                      SmartDialog.showToast('已忽略 $tagName');
                    },
                    child: Text(
                      '忽略此版本',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
                if (isAuto)
                  TextButton(
                    onPressed: () {
                      SmartDialog.dismiss();
                      GStorage.setting.put(SettingBoxKey.autoUpdate, false);
                    },
                    child: Text(
                      '不再提醒',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
                TextButton(
                  onPressed: SmartDialog.dismiss,
                  child: Text(
                    '取消',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
                if (Platform.isWindows) ...[
                  downloadBtn('zip', ext: 'zip'),
                  downloadBtn('exe', ext: 'exe'),
                ] else if (Platform.isLinux) ...[
                  downloadBtn('rpm', ext: 'rpm'),
                  downloadBtn('deb', ext: 'deb'),
                  downloadBtn('targz', ext: 'tar.gz'),
                ] else
                  downloadBtn('Github'),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
    }
  }

  static bool _hasUpdate({
    required String currentVersion,
    required String latestVersion,
    required int latestBuildTime,
    Object? assets,
  }) {
    if (_assetsContainCurrentBuild(assets)) {
      return false;
    }
    final compareResult = _compareVersion(currentVersion, latestVersion);
    if (compareResult != null) {
      return compareResult < 0;
    }
    return BuildConfig.buildTime < latestBuildTime;
  }

  static bool _assetsContainCurrentBuild(Object? assets) {
    if (assets is! List) {
      return false;
    }
    final currentBuild = '${BuildConfig.versionName}+${BuildConfig.versionCode}';
    return assets.any((asset) {
      if (asset is! Map) {
        return false;
      }
      return '${asset['name']}'.contains(currentBuild);
    });
  }

  static int? _compareVersion(String currentVersion, String latestVersion) {
    final current = _parseVersion(currentVersion);
    final latest = _parseVersion(latestVersion);
    if (current == null || latest == null) {
      return null;
    }
    final length = max(current.length, latest.length);
    for (int i = 0; i < length; i++) {
      final currentValue = i < current.length ? current[i] : 0;
      final latestValue = i < latest.length ? latest[i] : 0;
      if (currentValue != latestValue) {
        return currentValue.compareTo(latestValue);
      }
    }
    return 0;
  }

  static List<int>? _parseVersion(String version) {
    final match = RegExp(r'v?(\d+(?:\.\d+)*)').firstMatch(version);
    if (match == null) {
      return null;
    }
    return match
        .group(1)!
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
  }

  // 下载适用于当前系统的安装包
  static Future<void> onDownload(Map data, {String? ext}) async {
    SmartDialog.dismiss();
    try {
      void download(String plat) {
        final assets = data['assets'];
        if (assets is List && assets.isNotEmpty) {
          for (final asset in assets) {
            if (asset is! Map) {
              continue;
            }
            final String name = '${asset['name']}';
            if (name.contains(plat) &&
                (ext == null || ext.isEmpty ? true : name.endsWith(ext))) {
              PageUtils.launchURL('${asset['browser_download_url']}');
              return;
            }
          }
          throw UnsupportedError('platform not found: $plat');
        }
        throw UnsupportedError('release assets empty');
      }

      if (Platform.isAndroid) {
        // 获取设备信息
        AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
        // [arm64-v8a]
        download(androidInfo.supportedAbis.first);
      } else {
        download(Platform.operatingSystem);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('download error: $e');
      PageUtils.launchURL('${Constants.sourceCodeUrl}/releases/latest');
    }
  }
}
