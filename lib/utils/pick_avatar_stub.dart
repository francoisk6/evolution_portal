import 'dart:typed_data';

class PickedAvatarFile {
  final Uint8List bytes;
  final String name;
  final String? mime;
  const PickedAvatarFile({required this.bytes, required this.name, this.mime});
}

/// Non-web stub.
///
/// Avatar picking is not enabled here to avoid adding new platform plugins.
/// (If you want mobile support too, we can wire ImagePicker in your main app.)
Future<PickedAvatarFile?> pickAvatarFile() async {
  return null;
}
