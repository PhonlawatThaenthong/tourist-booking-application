import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/restaurant/restaurant_bloc.dart';
import '../../blocs/restaurant/restaurant_event.dart';
import '../../models/restaurant.dart';
import '../../services/maps_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/restaurant_photo.dart';

/// Everything about one restaurant: the details the list card leaves out to
/// stay scannable, plus the map and directions actions.
class RestaurantDetailScreen extends StatelessWidget {
  final Restaurant restaurant;
  const RestaurantDetailScreen({super.key, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    // The latest copy from the bloc, so a pull-to-refresh (say, after staff
    // upload a photo) updates this page; the one passed in is the fallback.
    final restaurant = context.select<RestaurantBloc, Restaurant>(
      (b) => b.state.restaurants.firstWhere(
        (r) => r.id == this.restaurant.id,
        orElse: () => this.restaurant,
      ),
    );
    final textTheme = Theme.of(context).textTheme;
    final muted = TextStyle(color: Colors.grey.shade600);

    return Scaffold(
      appBar: AppBar(
        title: Text(restaurant.name, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: () => reloadBloc(
          context.read<RestaurantBloc>(),
          const RestaurantStarted(),
        ),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            RestaurantPhoto(restaurant: restaurant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber.shade700, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        restaurant.rating.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '  ·  ${restaurant.priceRange}  ·  '
                        '${Format.distance(restaurant.distanceKm)} away',
                        style: muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _line(Icons.restaurant_menu, restaurant.cuisine, muted),
                  const Divider(height: 32),
                  Text(
                    'About',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    restaurant.description,
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Address',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _line(Icons.location_on_outlined, restaurant.address, muted),
                ],
              ),
            ),
          ],
        ),
      ),
      // Pinned, so the actions stay in reach however long the description is.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => MapsService.openLocation(
                    lat: restaurant.latitude,
                    lng: restaurant.longitude,
                    label: restaurant.name,
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View on map'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => MapsService.openDirections(
                    destLat: restaurant.latitude,
                    destLng: restaurant.longitude,
                  ),
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, TextStyle style) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
