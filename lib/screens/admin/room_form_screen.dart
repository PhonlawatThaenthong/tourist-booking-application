import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/room.dart';
import '../../providers/room_provider.dart';

/// Add or edit a room. When [existing] is null this creates a new room.
class RoomFormScreen extends StatefulWidget {
  final Room? existing;
  const RoomFormScreen({super.key, this.existing});

  @override
  State<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends State<RoomFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _capacity;
  late final TextEditingController _description;
  late final TextEditingController _images;
  late final TextEditingController _amenities;
  late RoomType _type;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _name = TextEditingController(text: r?.name ?? '');
    _price =
        TextEditingController(text: r?.pricePerNight.toStringAsFixed(0) ?? '');
    _capacity = TextEditingController(text: r?.capacity.toString() ?? '2');
    _description = TextEditingController(text: r?.description ?? '');
    _images = TextEditingController(text: r?.imageUrls.join('\n') ?? '');
    _amenities = TextEditingController(text: r?.amenities.join(', ') ?? '');
    _type = r?.type ?? RoomType.standard;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _capacity.dispose();
    _description.dispose();
    _images.dispose();
    _amenities.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<RoomProvider>();
    final imageUrls = _images.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final amenities = _amenities.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (_isEdit) {
      final r = widget.existing!;
      r
        ..name = _name.text.trim()
        ..type = _type
        ..pricePerNight = double.parse(_price.text)
        ..capacity = int.parse(_capacity.text)
        ..description = _description.text.trim()
        ..imageUrls = imageUrls.isEmpty ? r.imageUrls : imageUrls
        ..amenities = amenities;
      provider.updateRoom(r);
    } else {
      provider.addRoom(
        name: _name.text.trim(),
        type: _type,
        pricePerNight: double.parse(_price.text),
        capacity: int.parse(_capacity.text),
        description: _description.text.trim(),
        imageUrls: imageUrls,
        amenities: amenities,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit room' : 'Add room')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Room name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RoomType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Room type'),
              items: RoomType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Price/night', prefixText: '฿ '),
                    validator: (v) => double.tryParse(v ?? '') == null
                        ? 'Enter a number'
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Capacity'),
                    validator: (v) => int.tryParse(v ?? '') == null
                        ? 'Enter a number'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _images,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Image URLs (one per line)',
                helperText: 'Leave blank to use a default image',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amenities,
              decoration: const InputDecoration(
                labelText: 'Amenities (comma separated)',
                helperText: 'e.g. Wi-Fi, TV, Balcony',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: Text(_isEdit ? 'Save changes' : 'Add room'),
            ),
          ],
        ),
      ),
    );
  }
}
