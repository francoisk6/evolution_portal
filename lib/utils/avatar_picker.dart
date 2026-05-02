import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AvatarPickResult {
  final Uint8List bytes;
  final String filename;
  final String mimeType; // best-effort
  const AvatarPickResult({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}

class AvatarPicker {
  static final ImagePicker _picker = ImagePicker();

  static Future<AvatarPickResult?> pick(BuildContext context) async {
    final source = await showModalBottomSheet<_AvatarSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text("Change Avatar",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text("Use Camera"),
                onTap: () => Navigator.pop(ctx, _AvatarSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text("Upload / Gallery"),
                onTap: () => Navigator.pop(ctx, _AvatarSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (source == null) return null;

    try {
      final XFile? x = await _picker.pickImage(
        source: source == _AvatarSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 90,
      );
      if (x == null) return null;

      final bytes = await x.readAsBytes();
      final name = x.name.isNotEmpty ? x.name : "avatar.jpg";

      // simple mime inference
      final lower = name.toLowerCase();
      final mime = lower.endsWith(".png")
          ? "image/png"
          : lower.endsWith(".webp")
              ? "image/webp"
              : "image/jpeg";

      return AvatarPickResult(bytes: bytes, filename: name, mimeType: mime);
    } catch (_) {
      // If camera/gallery not available on a platform, just return null.
      return null;
    }
  }
}

enum _AvatarSource { camera, gallery }
