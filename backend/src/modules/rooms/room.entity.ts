import {
  Column, CreateDateColumn, Entity, Index, OneToMany, PrimaryGeneratedColumn, UpdateDateColumn,
} from 'typeorm';
import { numericTransformer } from '../../common/numeric.transformer';
import { Booking } from '../bookings/booking.entity';

/** Mirrors RoomType in frontend/lib/models/room.dart */
export enum RoomType {
  SINGLE = 'single',
  TWIN = 'twin',
}

/** Mirrors RoomStatus in frontend/lib/models/room.dart */
export enum RoomStatus {
  AVAILABLE = 'available',
  MAINTENANCE = 'maintenance',
}

@Entity('rooms')
export class Room {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ length: 120 })
  name!: string;

  @Column({ type: 'enum', enum: RoomType })
  type!: RoomType;

  @Column({
    name: 'price_per_night',
    type: 'numeric',
    precision: 10,
    scale: 2,
    transformer: numericTransformer,
  })
  pricePerNight!: number;

  @Column({ type: 'int' })
  capacity!: number;

  @Column({ type: 'text', default: '' })
  description!: string;

  @Column({ name: 'image_urls', type: 'text', array: true, default: () => `'{}'` })
  imageUrls!: string[];

  @Column({ type: 'text', array: true, default: () => `'{}'` })
  amenities!: string[];

  @Index()
  @Column({ type: 'enum', enum: RoomStatus, default: RoomStatus.AVAILABLE })
  status!: RoomStatus;

  @OneToMany(() => Booking, (b) => b.room)
  bookings!: Booking[];

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;
}
