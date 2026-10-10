import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// En la web, `record` devuelve un enlace `blob:` local del navegador.
Future<Uint8List> readRecording(String path) async => (await http.get(Uri.parse(path))).bodyBytes;
