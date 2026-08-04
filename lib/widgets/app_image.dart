import 'package:flutter/material.dart';

/// Renders either a network image or local asset image depending on the URL string.
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
      url.startsWith('http://') || url.startsWith('https://');

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

    return Image.asset(
      url,
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
