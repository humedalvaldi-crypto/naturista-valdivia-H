import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readRecording(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  try {
    await file.delete(); // el archivo temporal no se queda en el teléfono
  } catch (_) {
    // Si no se pudo borrar, el sistema limpia la carpeta temporal.
  }
  return bytes;
}
