import 'package:flutter/widgets.dart';

import 'api_client.dart';

/// Expone el [ApiClient] al árbol de widgets.
class ApiScope extends InheritedWidget {
  const ApiScope({super.key, required this.client, required super.child});

  final ApiClient client;

  static ApiClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ApiScope>();
    assert(scope != null, 'ApiScope no encontrado en el árbol de widgets.');
    return scope!.client;
  }

  @override
  bool updateShouldNotify(ApiScope oldWidget) => oldWidget.client != client;
}
