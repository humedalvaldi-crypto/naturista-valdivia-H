import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Foto elegida por la persona, lista para subir.
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.contentType, required this.name});

  final Uint8List bytes;
  final String contentType;
  final String name;
}

/// Tipo real de la imagen según sus primeros bytes (igual que el servidor).
String? sniffImageType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return 'image/jpeg';
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) return 'image/png';
  if (b.length >= 12 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

class UnsupportedPhotoException implements Exception {
  const UnsupportedPhotoException();
}

/// Punto único para elegir fotos. Las pruebas reemplazan [pick].
abstract final class PhotoPicker {
  static Future<PickedPhoto?> Function() pick = _pickFromGallery;

  static Future<PickedPhoto?> _pickFromGallery() async {
    // Se reduce a 2048 px y calidad 85 para no subir fotos enormes.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final type = sniffImageType(bytes);
    if (type == null) throw const UnsupportedPhotoException();
    return PickedPhoto(bytes: bytes, contentType: type, name: file.name);
  }
}
