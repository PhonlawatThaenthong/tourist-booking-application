import { Restaurant } from './restaurant.entity';

/** Shape the app reads; mirrors Restaurant in frontend/lib/models/restaurant.dart. */
export interface RestaurantResponse {
  id: string;
  name: string;
  cuisine: string;
  rating: number;
  priceRange: string;
  description: string;
  /**
   * An uploaded photo wins, as an API path (`/api/restaurants/:id/image`) the
   * app prefixes with its base URL. The `v` query changes with every upload,
   * so the app's image cache never keeps showing the old photo.
   * Otherwise the stored `image_url` fallback, which may be empty.
   */
  imageUrl: string;
  address: string;
  latitude: number;
  longitude: number;
}

export function toRestaurantResponse(r: Restaurant): RestaurantResponse {
  return {
    id: r.id,
    name: r.name,
    cuisine: r.cuisine,
    rating: r.rating,
    priceRange: r.priceRange,
    description: r.description,
    imageUrl: r.imagePath
      ? `/api/restaurants/${r.id}/image?v=${r.updatedAt.getTime()}`
      : r.imageUrl,
    address: r.address,
    latitude: r.latitude,
    longitude: r.longitude,
  };
}
