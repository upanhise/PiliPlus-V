# PiliPlus Fork 开发上下文

## 1. 项目概述
PiliPlus 是基于 Flutter/Dart 的 BiliBili 第三方客户端，支持 Android、iOS、Windows、Linux、macOS。

当前 fork/开发目标：在上游 PiliPlus 基础上持续开发，优先选择低耦合、可独立验证的小功能和 Bug 修复，逐步形成自己的维护分支。

## 2. 本地仓库信息
- 上游仓库：`https://github.com/bggRGjQaUbCoE/PiliPlus.git`
- 本地路径：`/var/minis/workspace/PiliPlus`
- 当前开发分支：`minis/dev-start`
- 默认上游分支：`main`

## 3. 技术栈
- 语言：Dart
- 框架：Flutter
- 状态/路由：GetX
- 网络：Dio + 项目封装 Request
- 本地存储：Hive/GStorage/SettingBoxKey
- 构建：GitHub Actions + Flutter stable，版本由 `pubspec.yaml`/`.fvmrc` 指定

## 4. 开发原则
1. 优先小步提交：一个功能或一个修复一个 commit。
2. 优先跟上游兼容：减少无关格式化和大范围重构。
3. 修改配置项时：
   - 在 `lib/utils/storage_key.dart` 增加 key。
   - 通过 `GStorage.setting.get/put` 读写。
   - 默认值必须兼容旧用户。
4. 网络/API 相关逻辑必须保留异常兜底，不能影响主流程。
5. UI 文案使用中文，保持项目现有风格。

## 5. 首批开发任务
| 优先级 | 任务 | 说明 | 状态 |
|---|---|---|---|
| P0 | 更新弹窗增加“忽略此版本” | 对应上游 issue #2415，用户可忽略当前 tag，后续自动检查不再提示该版本 | 进行中 |
| P1 | 站内搜索 | 对应 issue #2408，范围较大，待拆分 | 待定 |
| P1 | 直播切换线路 | 对应 issue #2420，需要阅读直播播放链路 | 待定 |
| P2 | APK 文件名包含完整版本号 | 对应 issue #2414，修改 GitHub Actions/脚本 | 待定 |

## 6. 验收标准
- 代码能通过 `dart format`/`flutter analyze`。
- Android 构建能通过 GitHub Actions 或本地 Flutter 环境。
- 对用户设置、登录状态、播放流程无破坏性影响。

## 7. 当前环境限制
当前 Android 沙箱内没有 Flutter/Dart SDK，无法直接本机编译 APK。代码开发可继续进行；最终构建建议使用 GitHub Actions、电脑本地 Flutter 环境，或配置远程 CI。
