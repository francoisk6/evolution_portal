import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedAvatarFile {
  final Uint8List bytes;
  final String name;
  final String? mime;
  const PickedAvatarFile({required this.bytes, required this.name, this.mime});
}

final ImagePicker _picker = ImagePicker();

String? _inferMimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

Future<PickedAvatarFile?> pickAvatarFromGallery() async {
  final XFile? x = await _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 90,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final name = x.name.isNotEmpty ? x.name : 'avatar.jpg';
  return PickedAvatarFile(bytes: bytes, name: name, mime: _inferMimeFromName(name));
}

Future<PickedAvatarFile?> pickAvatarFromCamera() async {
  final XFile? x = await _picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 90,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final name = x.name.isNotEmpty ? x.name : 'avatar.jpg';
  return PickedAvatarFile(bytes: bytes, name: name, mime: _inferMimeFromName(name));
}

/// Backwards-compatible alias (defaults to Gallery).
Future<PickedAvatarFile?> pickAvatarFile() => pickAvatarFromGallery();
