import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/room.dart';
import '../../blocs/room_cubit.dart';
import '../../utils/formatters.dart';
import 'room_form_screen.dart';

/// Room inventory management: add/remove rooms, update price, toggle the
/// maintenance status.
class ManageRoomsScreen extends StatelessWidget {
  const ManageRoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoomCubit>();
    final rooms = provider.allRooms;

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (_, i) => _RoomAdminCard(room: rooms[i]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoomFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add room'),
      ),
    );
  }
}

class _RoomAdminCard extends StatelessWidget {
  final Room room;
  const _RoomAdminCard({required this.room});

  Future<void> _editPrice(BuildContext context) async {
    final ctrl =
        TextEditingController(text: room.pricePerNight.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update price'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Price per night (฿)', prefixText: '฿ '),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      context.read<RoomCubit>().updatePrice(room.id, result);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove room?'),
        content: Text('Remove "${room.name}" from inventory?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<RoomCubit>().removeRoom(room.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<RoomCubit>();
    final maintenance = room.status == RoomStatus.maintenance;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.network(
                      room.primaryImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.king_bed_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('${room.type.label} · ${room.capacity} guests',
                          style: TextStyle(color: Colors.grey.shade600)),
                      Text('${Format.money(room.pricePerNight)} / night',
                          style: const TextStyle(
                              color: Color(0xFF00796B),
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (maintenance)
                  Chip(
                    label: const Text('Maintenance'),
                    backgroundColor: Colors.orange.shade100,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Row(
                  children: [
                    const Text('Maintenance'),
                    Switch(
                      value: maintenance,
                      onChanged: (v) => provider.setStatus(
                        room.id,
                        v ? RoomStatus.maintenance : RoomStatus.available,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit price',
                  icon: const Icon(Icons.attach_money),
                  onPressed: () => _editPrice(context),
                ),
                IconButton(
                  tooltip: 'Edit room',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => RoomFormScreen(existing: room)),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove room',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
