enum VipState {
  vip,
  nonVip,
  notLogin,
  unknown,
}

enum BangumiSourcePolicy {
  official,
  fallback,
}

extension BangumiSourcePolicyExt on BangumiSourcePolicy {
  String get displayName => switch (this) {
    BangumiSourcePolicy.official => '官方播放源',
    BangumiSourcePolicy.fallback => '自定义番剧源',
  };
}
