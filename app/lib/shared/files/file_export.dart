import 'dart:typed_data';

import 'file_export_io.dart' if (dart.library.js_interop) 'file_export_web.dart' as impl;

/// Entrega un archivo generado por la app: en la web lo descarga; en Android
/// abre el menú de compartir (guardar en Drive, enviar por WhatsApp, etc.).
abstract final class FileExport {
  static Future<void> Function(Uint8List bytes, String fileName, String mimeType) save = impl.saveFile;
}

/// Nombre de archivo seguro a partir de un título.
String safeFileName(String title, String ext) {
  final base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${base.isEmpty ? 'naturista-valdivia' : base}.$ext';
}
