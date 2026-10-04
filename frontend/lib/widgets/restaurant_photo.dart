import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import 'app_image.dart';

/// A restaurant's photo in a 16:9 frame, with a placeholder while it has
/// none. Wrapped in a [Hero] so it carries over from the list card to the
/// detail page.
class RestaurantPhoto extends StatelessWidget {
  final Restaurant restaurant;
  const RestaurantPhoto({super.key, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'restaurant-photo-${restaurant.id}',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        // AppImage handles both uploaded photos (served by the API) and any
        // bundled asset path.
        child: AppImage(
          url: restaurant.imageUrl,
          errorBuilder: (_) => Container(
            color: Colors.grey.shade200,
            child: Icon(
              Icons.restaurant,
              size: 48,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}
