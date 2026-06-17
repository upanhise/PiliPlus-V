# PiliPlus-V 开发进展报告

> 目标：让你快速知道这几天到底开发了什么、改了哪里、当前能用什么、还有什么没完成。  
> 分支：`minis/dev-start`  
> 仓库：`https://github.com/upanhise/PiliPlus-V`  
> 最新提交：`28dac825c fix: show bangumi source toast only on source changes`

---

## 一句话总结

这次主要完成了 **PiliPlus fork 的基础定制、更新逻辑修复、CI 自动构建、番剧源策略骨架、设置项安全加固、以及弹窗体验优化**。

当前 APK 已能通过 GitHub Actions 自动构建，用户下载 `Android_arm64-v8a` 即可安装测试。

---

## 1. 已完成的核心能力

### 1.1 Fork 仓库接管

已把项目开发切到你的 fork：

```text
https://github.com/upanhise/PiliPlus-V
```

本地开发分支：

```text
minis/dev-start
```

已经成功推送并由 GitHub Actions 自动构建。

---

### 1.2 自动构建 APK

新增并修复了 fork 专用 CI：

```text
.github/workflows/build-fork.yml
```

现在支持：

- push 自动构建
- PR 自动构建
- 手动触发构建
- 自动安装 Flutter
- 自动运行 `flutter pub get`
- 自动运行 `flutter analyze --no-fatal-infos`
- 如果有 `test/` 目录则运行 `flutter test`
- 自动生成 `pili_release.json`
- 自动构建三种 APK：
  - `arm64-v8a`
  - `armeabi-v7a`
  - `x86_64`
- artifact 缺失时直接失败，避免“构建成功但没有 APK”

最近一次已验证成功的构建：

```text
Actions run: 27510140508
```

最新一次因又提交了体验修复，正在重新构建：

```text
Actions run: 27511301243
```

---

## 2. 更新检查相关改动

### 2.1 更新源切换到 fork

应用内检查更新现在读取你的 fork：

```text
upanhise/PiliPlus-V
```

不再读上游仓库 release。

### 2.2 修复误报更新

之前可能出现：已经是最新版本，但仍弹更新。

已优化版本比较逻辑，支持这些格式：

```text
2.0.9
2.0.9.2
v2.0.9.2
2.0.9+5051
2.0.9-commit
2.0.9.2-minis.1
```

### 2.3 支持“忽略此版本”

更新弹窗新增：

```text
忽略此版本
```

规则：

- 自动检查更新时，忽略后不再提示同一版本
- 手动检查更新时，仍然可以看到该版本

---

## 3. 视频简介显示优化

视频简介里的提示信息变得更醒目，包括：

- 争议信息
- AI 生成内容提示

样式改成更明显的红色加粗，方便用户快速注意。

---

## 4. 自定义番剧源功能：当前状态

### 4.1 已做的部分

设置页新增了自定义番剧源相关入口：

```text
启用自定义番剧源
自定义番剧源地址
官方权限失败时尝试自定义番剧源
显示当前番剧源提示
```

但注意：

```text
当前只是安全骨架和配置入口，真实源接口还没有接入。
```

也就是说，当前版本不会内置任何第三方番剧源。

### 4.2 为什么先做骨架

因为直接接真实源之前，必须先解决这些基础问题：

- VIP 状态怎么判断
- 大会员是否允许降级
- 未登录怎么处理
- VIP 状态未知怎么处理
- 官方源失败时哪些错误可以 fallback
- 用户 URL 输入是否合法
- fallback 失败后是否误导用户
- 弹窗是否打扰用户

这些已经先做了。

---

## 5. 番剧源策略设计

### 5.1 VIP 状态分类

新增状态：

```dart
VipState.vip
VipState.nonVip
VipState.notLogin
VipState.unknown
```

策略：

| 状态 | 当前策略 |
|---|---|
| VIP | 走官方源，不自动降级 |
| 非 VIP | 官方权限失败时，可尝试自定义源 |
| 未登录 | 官方权限失败时，可尝试自定义源 |
| 未知 | 保守处理，不降级 |

### 5.2 播放前刷新 VIP 状态

播放番剧前会刷新一次主账号信息，避免本地缓存过旧导致误判。

同时做了 5 分钟节流：

```text
5 分钟内不重复请求用户信息
```

避免频繁请求。

### 5.3 官方权限失败检测

当前会识别这些错误文案：

```text
大会员
会员
试看
权限
专属
付费
购买
```

以及错误码：

```text
87007
87008
```

这些会被视为“可能需要 fallback 的官方权限失败”。

---

## 6. 自定义番剧源 URL 安全校验

保存源地址时会检查：

- 必须是 `http://` 或 `https://`
- 必须有 host
- 自动去掉尾部 `/`
- 空字符串允许保存，用于清空配置

非法示例会被拒绝：

```text
abc
file:///test
javascript:alert(1)
https://
```

合法示例：

```text
https://example.com/api/bangumi
```

如果主开关没打开，点击“自定义番剧源地址”只提示：

```text
请先启用自定义番剧源
```

---

## 7. 弹窗体验优化

你刚刚明确提出：

```text
自然无感，没有必要的弹窗通知就不弹。
```

已经记住，后续开发会按这个原则走。

### 7.1 当前已改的弹窗策略

之前：

```text
只要番剧播放成功，就可能提示当前使用官方播放源。
```

现在：

```text
首次使用官方源：不提示
一直使用官方源：不提示
切清晰度仍是官方源：不提示
重连仍是官方源：不提示
只有官方源和自定义源发生切换时才提示
```

提示文案：

```text
已切换至官方播放源
已切换至自定义番剧源
```

### 7.2 初步弹窗分级建议

后续可以按这个等级处理：

#### P0：必须打断

必须让用户知道，否则会造成明显风险或操作失败。

例如：

- 登录失效
- 支付/权限失败
- 文件保存失败
- 下载失败
- 明确的危险操作确认

#### P1：轻提示

用户需要知道，但不应该打断流程。

例如：

- 已保存
- 已复制
- 已切换播放源
- 自动 fallback 成功

这类建议用短 toast，且要去重。

#### P2：可静默

用户不一定需要知道，默认不弹。

例如：

- 正常使用官方源
- 后台刷新成功
- 缓存命中
- 自动选择默认策略

#### P3：只写日志

开发调试需要，但用户不需要。

例如：

- 当前策略判断
- 请求参数
- fallback 未触发原因
- VIP 状态刷新被节流

---

## 8. 当前未完成/后续可做

### 8.1 真实自定义番剧源协议

当前只是配置入口，没有真实拉流接口。

下一步如果要做，需要定义接口协议，例如：

```http
GET https://example.com/api/bangumi/play?cid=xxx&ep_id=xxx&season_id=xxx&bvid=xxx
```

返回：

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "url": "https://example.com/video.m3u8",
    "format": "hls",
    "quality": 80
  }
}
```

然后把它转换成 PiliPlus 当前播放器能识别的 `PlayUrlModel`。

### 8.2 弹窗分级落地

建议你体验几天后，我们再统一整理：

- 哪些提示删掉
- 哪些改成静默
- 哪些合并
- 哪些只在失败时出现
- 哪些只写 debug log

### 8.3 Release 页面说明

现在 Actions artifact 已包含说明文件，但 GitHub Release 页面还没有正式发布说明。

后续可以做：

- 自动创建 release
- 自动上传 APK
- 自动生成 release notes

这样普通用户就不用进 Actions 下载。

---

## 9. 主要提交记录

```text
5b851aed3 feat: ignore specific update version
810fd6504 docs: expand fork development SDD
2ffe2a238 chore: use release tag for android artifact name
3c42ae8d0 fix: compare release version before update prompt
52330a13c docs: add fork changelog
9c3897377 chore: point update source to fork releases
3d573c93d style: highlight AI generated content label
a59f1aeb0 feat: bangumi custom source policy scaffold + error fixes
fb02d4145 fix: harden bangumi source policy UX and validation
e882d14d9 fix: resolve remaining bangumi review findings
cf07be51a ci: avoid failing fork build on existing info lints
6f35fe106 ci: generate release metadata before fork APK build
28dac825c fix: show bangumi source toast only on source changes
```

---

## 10. 当前结论

当前阶段已经完成：

```text
fork 可自动构建 + 更新逻辑修复 + 番剧源策略骨架 + 设置安全校验 + 弹窗体验初步优化
```

建议你接下来体验几天，重点观察：

1. 有没有多余弹窗
2. 更新检查是否符合预期
3. 视频简介提示是否太显眼或刚好
4. 设置页是否容易理解
5. 番剧播放是否有明显变慢
6. 是否需要真正接入自定义番剧源协议
