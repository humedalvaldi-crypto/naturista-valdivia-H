import 'package:flutter/foundation.dart';

import '../../features/social/domain/models.dart';

typedef PageLoader<T> = Future<ResultPage<T>> Function(String? cursor);

/// Lista paginada por cursor con estados de carga y error.
class PagedController<T> extends ChangeNotifier {
  PagedController(this._load);

  final PageLoader<T> _load;

  List<T> items = [];
  String? _next;
  bool loading = false;
  bool loadingMore = false;
  Object? error;
  bool _loaded = false;

  bool get hasMore => _next != null;
  bool get isEmpty => _loaded && items.isEmpty && error == null;
  bool get initialLoading => loading && !_loaded;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _load(null);
      items = page.items;
      _next = page.nextCursor;
      _loaded = true;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await _load(cursor);
      items = [...items, ...page.items];
      _next = page.nextCursor;
    } catch (e) {
      error = e;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void replace(bool Function(T) test, T value) {
    items = [for (final i in items) test(i) ? value : i];
    notifyListeners();
  }

  void insertFirst(T value) {
    items = [value, ...items];
    _loaded = true;
    notifyListeners();
  }

  void remove(bool Function(T) test) {
    items = items.where((i) => !test(i)).toList();
    notifyListeners();
  }
}
