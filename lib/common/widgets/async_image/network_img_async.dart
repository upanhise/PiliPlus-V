import 'dart:async';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 异步获取图片地址后渲染的组件。
/// 适用场景：图片 URL 需要从 API、缓存、或计算中异步取得（非静态已知地址）。
/// 使用示例：
/// ```dart
/// AsyncImage.fromFuture(
///   future: computeImageUrl(item),
///   width: 120,
///   height: 80,
///   placeholder: (_) => const SkeletonImage(),
/// )
/// ```
/// Markdown 风格：`![${item.content}]($url)` → 组件内部异步解析 url。
class AsyncImage extends StatelessWidget {
  const AsyncImage({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fadeDuration = const Duration(milliseconds: 120),
    this.cacheWidth,
  });

  /// 静态已知地址时直接传入 String（兼容用法）
  final String? src;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  final Duration fadeDuration;
  final int? cacheWidth;

  /// 通过 Future 构建：先展示 placeholder，等 Future 完成后切到真实图片
  static Widget fromFuture({
    required Future<String?> future,
    required double width,
    required double height,
    Key? key,
    BorderRadius borderRadius = BorderRadius.zero,
    BoxFit fit = BoxFit.cover,
    Duration fadeDuration = const Duration(milliseconds: 120),
    Widget Function(BuildContext)? placeholder,
    Widget Function(BuildContext, Object)? errorBuilder,
    int? cacheWidth,
  }) {
    return FutureBuilder<String?>(
      key: key,
      future: future,
      builder: (context, snapshot) {
        // 加载中：展示骨架或占位图
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _Placeholder(
            width: width,
            height: height,
            borderRadius: borderRadius,
            placeholder: placeholder,
          );
        }

        // 出错了
        if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
          return _ErrorView(
            width: width,
            height: height,
            borderRadius: borderRadius,
            errorBuilder: errorBuilder,
            error: snapshot.error,
          );
        }

        // 渲染真实图片
        return _ buildImage(
          context,
          src: snapshot.data!,
          width: width,
          height: height,
          borderRadius: borderRadius,
          fit: fit,
          fadeDuration: fadeDuration,
          cacheWidth: cacheWidth,
        );
      },
    );
  }

  /// 带缓存重试的异步加载：如果 future 报错，可点击重试
  static Widget fromFutureRetryable({
    required Future<String?> Function() futureBuilder,
    required double width,
    required double height,
    Key? key,
    BorderRadius borderRadius = BorderRadius.zero,
    BoxFit fit = BoxFit.cover,
    Duration fadeDuration = const Duration(milliseconds: 120),
    int? cacheWidth,
  }) {
    return _RetryableAsyncImage(
      key: key,
      futureBuilder: futureBuilder,
      width: width,
      height: height,
      borderRadius: borderRadius,
      fit: fit,
      fadeDuration: fadeDuration,
      cacheWidth: cacheWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (src == null || src!.isEmpty) {
      return _Placeholder(
        width: width,
        height: height,
        borderRadius: borderRadius,
        placeholder: placeholder,
      );
    }
    return _buildImage(
      context,
      src: src!,
      width: width,
      height: height,
      borderRadius: borderRadius,
      fit: fit,
      fadeDuration: fadeDuration,
      cacheWidth: cacheWidth,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }

  static Widget _buildImage(
    BuildContext context, {
    required String src,
    required double width,
    required double height,
    required BorderRadius borderRadius,
    required BoxFit fit,
    required Duration fadeDuration,
    int? cacheWidth,
    PlaceholderWidgetBuilder? placeholder,
    LoadingErrorWidgetBuilder? errorWidget,
  }) {
    Widget child = CachedNetworkImage(
      imageUrl: src,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeDuration,
      fadeOutDuration: fadeDuration,
      memCacheWidth: cacheWidth,
      placeholder: placeholder ??
          (_, __) => Container(
                width: width,
                height: height,
                color: Colors.grey.shade200,
              ),
      errorWidget: errorWidget ??
          (_, __, ___) => Container(
                width: width,
                height: height,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
    );

    if (borderRadius != BorderRadius.zero) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return child;
  }
}

/// 内部重试控件
class _RetryableAsyncImage extends StatefulWidget {
  const _RetryableAsyncImage({
    super.key,
    required this.futureBuilder,
    required this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
    this.fit = BoxFit.cover,
    this.fadeDuration = const Duration(milliseconds: 120),
    this.cacheWidth,
  });

  final Future<String?> Function() futureBuilder;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final Duration fadeDuration;
  final int? cacheWidth;

  @override
  State<_RetryableAsyncImage> createState() => _RetryableAsyncImageState();
}

class _RetryableAsyncImageState extends State<_RetryableAsyncImage> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.futureBuilder();
  }

  void _retry() {
    setState(() {
      _future = widget.futureBuilder();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _Placeholder(
            width: widget.width,
            height: widget.height,
            borderRadius: widget.borderRadius,
          );
        }
        if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
          return GestureDetector(
            onTap: _retry,
            child: _ErrorView(
              width: widget.width,
              height: widget.height,
              borderRadius: widget.borderRadius,
              error: snapshot.error,
            ),
          );
        }
        return AsyncImage._buildImage(
          context,
          src: snapshot.data!,
          width: widget.width,
          height: widget.height,
          borderRadius: widget.borderRadius,
          fit: widget.fit,
          fadeDuration: widget.fadeDuration,
          cacheWidth: widget.cacheWidth,
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
    this.placeholder,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Widget Function(BuildContext)? placeholder;

  @override
  Widget build(BuildContext context) {
    Widget child = placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
        );
    if (borderRadius != BorderRadius.zero) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return child;
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
    this.errorBuilder,
    this.error,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Widget Function(BuildContext, Object?)? errorBuilder;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    Widget child = errorBuilder?.call(context, error) ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
    if (borderRadius != BorderRadius.zero) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return child;
  }
}

/// Markdown `![alt](url)` 风格的异步解析工具。
/// 当 url 部分需要异步计算时使用。
/// 示例：
/// ```dart
/// // item.content = '这是图片说明'
/// // 图片地址需要从接口异步拿
/// AsyncImage.fromMarkdown(
///   alt: item.content,
///   urlFuture: resolveImageUrl(item.id),
///   width: 120,
///   height: 80,
/// )
/// ```
extension AsyncImageMarkdownExt on AsyncImage {
  static Widget fromMarkdown({
    required String? alt,
    required Future<String?> urlFuture,
    required double width,
    required double height,
    Key? key,
    BorderRadius borderRadius = BorderRadius.zero,
    BoxFit fit = BoxFit.cover,
    Duration fadeDuration = const Duration(milliseconds: 120),
    int? cacheWidth,
  }) {
    return AsyncImage.fromFuture(
      key: key,
      future: urlFuture,
      width: width,
      height: height,
      borderRadius: borderRadius,
      fit: fit,
      fadeDuration: fadeDuration,
      cacheWidth: cacheWidth,
    );
  }
}
