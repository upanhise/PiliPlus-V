# PiliPlus Fork SDD

## 1. 概述
PiliPlus 是基于 Flutter/Dart 的 BiliBili 第三方客户端，支持 Android、iOS、Pad、Windows、Linux、macOS。

当前项目目标：从上游 `bggRGjQaUbCoE/PiliPlus` fork 出一个可持续维护的分支，在尽量兼容上游的前提下，逐步实现用户关心的小功能、Bug 修复和构建/发布优化。

核心用户：
- 使用 PiliPlus 观看视频、直播、动态、收藏、稍后再看等内容的普通用户。
- 想要基于 PiliPlus 做二次开发、私有构建或自定义功能的维护者。

核心价值：
- 保持上游功能完整可用。
- 每次只做小而清晰的增量改动。
- 所有改动可追踪、可回滚、可通过 patch 或 fork 分支交付。

## 2. 本地仓库信息
- 上游仓库：`https://github.com/bggRGjQaUbCoE/PiliPlus.git`
- 本地路径：`/var/minis/workspace/PiliPlus`
- 当前开发分支：`minis/dev-start`
- 上游 remote：`upstream`
- 用户 fork remote：待用户提供 GitHub fork 地址后添加为 `origin`

## 3. 技术栈
- 语言：Dart
- 框架：Flutter
- 状态管理/路由：GetX
- 网络请求：Dio + 项目封装 `Request`
- 本地存储：Hive / `GStorage` / `SettingBoxKey` / `Pref`
- 媒体播放：项目自定义 `pl_player` + media_kit/mpv 相关能力
- 构建发布：GitHub Actions + Flutter stable；Flutter 版本由 `pubspec.yaml` 与 `.fvmrc` 指定

## 4. 功能模块
| 模块 | 功能点 | 优先级 | 开发策略 |
|---|---|---:|---|
| Fork 基础设施 | remote 整理、开发分支、项目上下文、patch 导出 | P0 | 已完成首轮 |
| 更新体验 | 自动更新弹窗、忽略指定版本、下载跳转 | P0 | 小步修改，优先不影响默认行为 |
| 构建发布 | APK 文件名、版本号、CI artifact、release 脚本 | P1 | 优先改 GitHub Actions 和脚本 |
| 搜索能力 | 站内搜索入口、搜索结果聚合、历史记录 | P1 | 先读现有搜索模块，拆成子任务 |
| 直播播放 | 直播线路切换、画质、CDN、播放失败兜底 | P1 | 先梳理 live http/model/player 链路 |
| 可访问性 | 语义标签、读屏、控件可点击区域 | P2 | 按页面逐步修复 |
| 用户自定义 | 主题、字体、布局、下载路径 | P2 | 配置项必须向后兼容 |

## 5. 数据与配置设计
本项目不是传统后端应用，无集中数据库迁移；主要状态保存在本地 Hive box。

关键约定：
- 新增设置 key：统一添加到 `lib/utils/storage_key.dart` 的 `SettingBoxKey`。
- 新增读取入口：优先添加到 `lib/utils/storage_pref.dart` 的 `Pref` getter。
- 写入设置：使用 `GStorage.setting.put(SettingBoxKey.xxx, value)`。
- 默认值：必须保证旧用户升级后不崩溃、不改变关键行为。
- 敏感信息：WebDAV 密码、Cookie、Token 等不得写入日志或文档。

当前新增配置：
| Key | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `ignoredUpdateVersion` | String | `''` | 自动更新时忽略指定 release tag |

## 6. API / 外部接口概要
| 场景 | 入口 | 说明 |
|---|---|---|
| 检查更新 | `Update.checkUpdate` → `Api.latestApp` | 获取 GitHub latest release 信息 |
| 下载更新 | `Update.onDownload` | 根据平台/ABI 打开对应下载 URL |
| B 站业务请求 | `lib/http/*` / `lib/grpc/*` | 由现有模块封装 |
| 本地播放 | `lib/plugin/pl_player/*` | 播放控制、弹幕、画质、截图等 |

## 7. 开发顺序
### Milestone 0：接管项目
- [x] 克隆上游仓库
- [x] 建立 `minis/dev-start` 分支
- [x] remote 改为 `upstream`
- [x] 创建项目 SDD / AI 配置
- [ ] 添加用户 fork 为 `origin`
- [ ] 推送开发分支

### Milestone 1：低风险功能修复
Commit 节点：
1. `feat: ignore specific update version`
   - 新增忽略当前更新版本能力。
   - 自动检查时跳过被忽略 tag。
   - 手动检查不跳过，方便用户重新查看。
2. `chore: include full version in android artifact name`
   - 处理安装包文件名完整版本号。
3. `fix: improve update dialog fallback handling`
   - 加强 release/assets 为空时的容错。

### Milestone 2：直播线路切换调研与实现
- 阅读 `lib/http/live.dart`
- 阅读 `lib/pages/live_room/*`
- 阅读 `lib/plugin/pl_player/*`
- 找到直播 URL/CDN/线路数据结构
- 先做只读线路列表，再做切换重载

### Milestone 3：站内搜索拆分
- 梳理已有搜索页：`lib/pages/common/search`、`lib/pages/search*`
- 明确“站内搜索”范围：视频、番剧、用户、直播、专栏、动态？
- 先实现单入口聚合页，再逐项扩展

## 8. 单模块开发循环
每个模块必须按以下流程：
1. 明确需求边界。
2. 读相关源码。
3. 写最小可行改动。
4. 查看 `git diff`。
5. 能跑测试就跑测试；当前沙箱无 Flutter SDK 时至少执行 `git diff --check`。
6. 做 Code Review。
7. 用户确认后 commit。
8. 导出 patch 到 `/var/minis/mounts/Openminis/PiliPlus-fork/`。

## 9. 验收标准
通用验收：
- 代码风格与项目一致。
- 不做无关格式化。
- 新增设置项有默认值。
- 异常路径有兜底。
- `git diff --check` 无 whitespace 错误。

理想构建验收：
- `dart format` / `flutter analyze` 通过。
- Android release 构建通过：
  `flutter build apk --release --split-per-abi --pub`
- GitHub Actions artifact 正常产出。

当前环境验收：
- 当前 Android 沙箱没有 Flutter/Dart SDK，无法本机编译 APK。
- 本地先做静态 diff 检查与 patch 导出。
- 最终构建通过外部 Flutter 环境或 GitHub Actions 完成。

## 10. 当前状态
已完成首个开发提交：
- Commit：`5b851aed3 feat: ignore specific update version`
- Patch：`/var/minis/mounts/Openminis/PiliPlus-fork/0001-feat-ignore-specific-update-version.patch`

待用户确认：
1. 是否认可这份 SDD 作为后续开发总纲。
2. 提供 GitHub fork 地址，用于添加 `origin` 并推送分支。
3. 选择下一个开发任务：构建发布优化、直播线路切换、站内搜索，或其他指定需求。
