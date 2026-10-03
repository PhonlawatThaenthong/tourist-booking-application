import {
  Column, CreateDateColumn, Entity, PrimaryGeneratedColumn, UpdateDateColumn,
} from 'typeorm';
import { numericTransformer } from '../../common/numeric.transformer';

/** Mirrors Restaurant in frontend/lib/models/restaurant.dart. No FK to any
 * other table — see docs/database-schema.md section 3.7. */
@Entity('restaurants')
export class Restaurant {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ length: 120 })
  name!: string;

  @Column({ length: 60 })
  cuisine!: string;

  @Column({
    type: 'numeric', precision: 2, scale: 1, transformer: numericTransformer,
  })
  rating!: number;

  @Column({ name: 'price_range', length: 10 })
  priceRange!: string;

  @Column({ type: 'text' })
  description!: string;

  /** Fallback when no photo has been uploaded: an external link, or empty. */
  @Column({ name: 'image_url', length: 500, default: '' })
  imageUrl!: string;

  /** Uploaded photo, relative to UPLOAD_DIR (like `payments.slip_path`). */
  @Column({ name: 'image_path', type: 'varchar', length: 255, nullable: true })
  imagePath!: string | null;

  @Column({ length: 255 })
  address!: string;

  @Column({
    type: 'numeric', precision: 9, scale: 6, transformer: numericTransformer,
  })
  latitude!: number;

  @Column({
    type: 'numeric', precision: 9, scale: 6, transformer: numericTransformer,
  })
  longitude!: number;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;
}
