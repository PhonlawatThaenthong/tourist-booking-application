import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/room.dart';
import '../../blocs/room/room_bloc.dart';
import '../../blocs/room/room_event.dart';
import '../../widgets/app_image.dart';

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
  late final TextEditingController _amenities;
  late RoomType _type;
  late List<String> _imageUrls;

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
    _amenities = TextEditingController(text: r?.amenities.join(', ') ?? '');
    _type = r?.type ?? RoomType.standard;
    _imageUrls = List.of(r?.imageUrls ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _capacity.dispose();
    _description.dispose();
    _amenities.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery / computer'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() => _imageUrls.add(picked.path));
    }
  }

  void _removePhoto(int index) {
    setState(() => _imageUrls.removeAt(index));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<RoomBloc>();
    final imageUrls = _imageUrls;
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
        ..imageUrls = imageUrls
        ..amenities = amenities;
      provider.add(RoomUpdateRequested(r));
    } else {
      provider.add(RoomAddRequested(
        name: _name.text.trim(),
        type: _type,
        pricePerNight: double.parse(_price.text),
        capacity: int.parse(_capacity.text),
        description: _description.text.trim(),
        imageUrls: imageUrls,
        amenities: amenities,
      ));
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
            Text('Photos', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _imageUrls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 96,
                              height: 96,
                              child: AppImage(
                                  url: _imageUrls[i], fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => _removePhoto(i),
                              child: const CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  InkWell(
                    onTap: _addPhoto,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined,
                          color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              'Upload from your phone (camera/gallery) or computer files. Leave empty to use a default image.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
