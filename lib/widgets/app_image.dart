import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Renders a network image, a bundled asset, or a local file (picked from
/// the device/computer) depending on the shape of the URL string.
class AppImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget Function(BuildContext context)? placeholderBuilder;
  final Widget Function(BuildContext context)? errorBuilder;

  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  bool get _isNetwork =>
      url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('blob:');

  // Bundled assets are declared under the `image/` folder in pubspec.yaml.
  bool get _isAsset => url.startsWith('image/');

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return errorBuilder?.call(context) ?? _defaultPlaceholder();
    }

    if (_isNetwork) {
      return Image.network(
        url,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholderBuilder?.call(context) ??
              Container(
                color: Colors.grey.shade200,
                child: const Center(child: CircularProgressIndicator()),
              );
        },
        errorBuilder: (ctx, err, stack) =>
            errorBuilder?.call(ctx) ?? _defaultPlaceholder(),
      );
    }

    if (_isAsset) {
      return Image.asset(
        url,
        fit: fit,
        errorBuilder: (ctx, err, stack) =>
            errorBuilder?.call(ctx) ?? _defaultPlaceholder(),
      );
    }

    // Anything else is a local file path picked from the device/computer.
    if (kIsWeb) {
      return errorBuilder?.call(context) ?? _defaultPlaceholder();
    }
    return Image.file(
      File(url),
      fit: fit,
      errorBuilder: (ctx, err, stack) =>
          errorBuilder?.call(ctx) ?? _defaultPlaceholder(),
    );
  }

  Widget _defaultPlaceholder() => Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.king_bed_outlined, size: 48, color: Colors.grey),
        ),
      );
}
