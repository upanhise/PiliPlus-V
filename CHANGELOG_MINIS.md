# Minis Fork 改动日志

记录 `minis/dev-start` 分支相对上游 `main` 的增量改动。

## Unreleased

### Added
- 新增项目开发总纲 `CLAUDE.md`，用于记录 fork 目标、技术栈、开发顺序、验收标准和当前限制。
- 新增 `.claude/settings.json`，记录 AI 协作开发规则。
- 更新弹窗新增“忽略此版本”按钮：
  - 自动检查更新时，可忽略当前 release tag。
  - 忽略后自动检查不再提示该版本。
  - 手动检查更新仍可重新查看。

### Changed
- Android GitHub Actions 构建产物文件名优先使用完整 release tag：
  - 例如 release tag 为 `2.0.9.2` 时，APK 文件名形如 `PiliPlus_android_2.0.9.2_arm64-v8a.apk`。
  - 无 release tag 的临时构建保留旧版本号策略，并增加兜底 dev 文件名。
- 更新检查逻辑改为优先比较 release tag / 应用版本号，解析失败时才回退到 release 创建时间比较。
- Fork 版本的源码链接和更新检查源切换到 `upanhise/PiliPlus-V`，应用内检查更新会读取 fork 仓库 release。
- 视频简介中的争议信息/AI 生成内容提示改为更醒目的红色加粗样式，提升可见性。
- 新增番剧播放源策略脚手架：统一主账号会员状态判断、官方源权限失败后的备用源接口占位、日志与失败提示。
- 新增自定义番剧源设置骨架：启用开关、源地址、官方失败后是否尝试、当前源提示开关。
- Fork CI 工作流更名为 `Build Fork`，增加 `flutter pub get`、`flutter analyze`、可选 `flutter test`、可选 release signing，并在缺少 APK artifact 时直接失败。

### Fixed
- 番剧播放前刷新主账号 VIP 状态并做 5 分钟节流，降低本地缓存陈旧导致误降级的风险。
- 当前番剧源提示增加 5 秒去重，避免切清晰度、重连等场景重复弹 toast。
- 自定义番剧源地址保存时增加 `http(s)` URL 校验与尾斜杠归一化；主开关关闭时禁止编辑地址。
- 明确自定义番剧源仍处于接口开发阶段，避免设置入口文案误导。
- 修复已安装最新版本但仍可能弹出更新提示的问题：
  - 支持比较 `2.0.9`、`2.0.9.2`、`v2.0.9.2`、`2.0.9+5051`、`2.0.9-commit`、`2.0.9.2-minis.1` 等版本格式。
  - 如果 release assets 文件名已包含当前 `versionName+versionCode`，直接判定为已是最新。
- 更新下载逻辑增加 assets 为空或格式异常时的兜底，避免按钮点击无反馈。

### Commits
- `5b851aed3 feat: ignore specific update version`
- `810fd6504 docs: expand fork development SDD`
- `2ffe2a238 chore: use release tag for android artifact name`
- `3c42ae8d0 fix: compare release version before update prompt`
- `52330a13c docs: add fork changelog`
- `9c3897377 chore: point update source to fork releases`
- `3d573c93d style: highlight AI generated content label`
- `a59f1aeb0 feat: bangumi custom source policy scaffold + error fixes`
- `fb02d4145 fix: harden bangumi source policy UX and validation`

### Validation
- 已执行 `git diff --check`。
- 已用等价 Python smoke test 验证版本比较核心场景。
- 当前 Android 沙箱无 Flutter/Dart SDK，尚未本机执行 `flutter analyze` 或 APK 构建；需通过 GitHub Actions 或外部 Flutter 环境验证。
