import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

/// Imagen servida por la API que puede ser privada: se descarga con la
/// sesión (Authorization) en vez de `Image.network`, que no envía el token.
class ApiImage extends StatefulWidget {
  const ApiImage({super.key, required this.api, required this.path, this.fit = BoxFit.cover});

  final ApiClient api;
  final String path;
  final BoxFit fit;

  /// Caché en memoria por ruta (las fotos de una página se repintan a menudo).
  static final Map<String, Future<Uint8List>> _cache = {};

  /// Imágenes guardadas en memoria ahora mismo.
  static int get cachedCount => _cache.length;

  /// Libera la memoria de imágenes; se vuelven a descargar al verlas.
  static void clearCache() {
    _cache.clear();
    PaintingBinding.instance.imageCache.clear();
  }
  static const _maxCached = 60;

  static Future<Uint8List> _load(ApiClient api, String path) {
    final cached = _cache[path];
    if (cached != null) return cached;
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    final future = api.getBytes(path).then(Uint8List.fromList);
    _cache[path] = future;
    // Un error no queda en caché: se reintenta la próxima vez.
    future.catchError((Object _) {
      _cache.remove(path);
      return Uint8List(0);
    });
    return future;
  }

  @override
  State<ApiImage> createState() => _ApiImageState();
}

class _ApiImageState extends State<ApiImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiImage._load(widget.api, widget.path);
  }

  @override
  void didUpdateWidget(ApiImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _future = ApiImage._load(widget.api, widget.path);
  }

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.image_outlined)));
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return placeholder;
        return Image.memory(bytes, fit: widget.fit, gaplessPlayback: true, errorBuilder: (context, _, _) => placeholder);
      },
    );
  }
}
