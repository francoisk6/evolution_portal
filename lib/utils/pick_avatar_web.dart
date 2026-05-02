// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

class PickedAvatarFile {
  final Uint8List bytes;
  final String name;
  final String? mime;
  const PickedAvatarFile({required this.bytes, required this.name, this.mime});
}

Future<PickedAvatarFile?> _pick({bool captureCamera = false}) async {
  final input = html.FileUploadInputElement()..accept = 'image/*';

  // On mobile browsers, capture hints can open the camera.
  if (captureCamera) {
    // 'environment' is back camera on many devices.
    input.setAttribute('capture', 'environment');
  }

  input.click();

  await input.onChange.first;
  final file = input.files?.isNotEmpty == true ? input.files!.first : null;
  if (file == null) return null;

  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoadEnd.first;

  final result = reader.result;
  if (result is! ByteBuffer) return null;

  return PickedAvatarFile(
    bytes: Uint8List.view(result),
    name: file.name,
    mime: file.type,
  );
}

Future<PickedAvatarFile?> pickAvatarFromGallery() => _pick(captureCamera: false);
Future<PickedAvatarFile?> pickAvatarFromCamera() => _pick(captureCamera: true);

/// Backwards-compatible alias (defaults to Gallery).
Future<PickedAvatarFile?> pickAvatarFile() => pickAvatarFromGallery();
