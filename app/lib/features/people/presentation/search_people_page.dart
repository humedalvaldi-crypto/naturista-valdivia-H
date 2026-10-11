import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../social/data/social_api.dart';
import '../../social/domain/models.dart';
import '../../social/presentation/person_avatar.dart';
import 'follow_confirm.dart';

/// Buscador de personas: resultados reales del servidor, paginados, y
/// sugerencias basadas en a quién sigues.
class SearchPeoplePage extends StatefulWidget {
  const SearchPeoplePage({super.key});

  static const minChars = 2;

  @override
  State<SearchPeoplePage> createState() => _SearchPeoplePageState();
}

class _SearchPeoplePageState extends State<SearchPeoplePage> {
  late SocialApi _api;
  final _input = TextEditingController();
  Timer? _debounce;

  /// Cada búsqueda tiene un número; se descartan respuestas de búsquedas viejas.
  int _seq = 0;
  String _query = '';
  List<PersonResult> _results = [];
  String? _cursor;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  List<PersonResult>? _suggestions;
  Object? _suggestionsError;
  bool _suggestionsRequested = false;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = SocialApi(ApiScope.of(context));
    if (!_suggestionsRequested && _api.isConfigured && AuthScope.read(context).isSignedIn) {
      _suggestionsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSuggestions();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _suggestionsError = null);
    try {
      final list = await _api.suggestions();
      if (mounted) setState(() => _suggestions = list);
    } catch (e) {
      if (mounted) setState(() => _suggestionsError = e);
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text.trim()));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    if (q.length < SearchPeoplePage.minChars) {
      setState(() {
        _query = q;
        _results = [];
        _cursor = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.searchPeople(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = page.items;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    final seq = _seq;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loadingMore = true);
    try {
      final page = await _api.searchPeople(_query, cursor: cursor);
      if (!mounted || seq != _seq) return;
      setState(() {
        final seen = _results.map((r) => r.person.id).toSet();
        _results = [..._results, ...page.items.where((r) => !seen.contains(r.person.id))];
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  void _replace(String id, PersonResult Function(PersonResult r) change) {
    setState(() {
      _results = [for (final r in _results) r.person.id == id ? change(r) : r];
      final s = _suggestions;
      if (s != null) _suggestions = [for (final r in s) r.person.id == id ? change(r) : r];
    });
  }

  Future<void> _toggleFollow(PersonResult r) async {
    if (!AuthScope.read(context).isSignedIn) {
      context.go(Uri(path: '/login', queryParameters: {'from': '/people/search'}).toString());
      return;
    }
    final follow = !r.followedByMe;
    if (!follow && !await confirmUnfollow(context, r.person.name)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final id = r.person.id;
    setState(() => _busy.add(id));
    _replace(id, (x) => x.copyWith(followedByMe: follow));
    try {
      await _api.setFollowing(id, follow);
    } catch (e) {
      _replace(id, (x) => x.copyWith(followedByMe: !follow));
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Widget _row(PersonResult r, {required bool isMe}) {
    final l10n = context.l10n;
    final p = r.person;
    final chips = [
      if (r.followsMe) l10n.followsYou,
      if (r.mutuals != null && r.mutuals! > 0) l10n.mutualsCount(r.mutuals!),
    ];
    final busy = _busy.contains(p.id);
    return ListTile(
      key: Key('person-result-${p.id}'),
      onTap: () => context.push('/people/${p.id}'),
      leading: PersonAvatar(person: p, imageUrl: _api.url(p.photo)),
      title: Text(p.name),
      subtitle: Text([if (p.username != null) '@${p.username}', ...chips].join(' · ')),
      trailing: isMe
          ? null
          : r.followedByMe
              ? OutlinedButton(key: Key('unfollow-${p.id}'), onPressed: busy ? null : () => _toggleFollow(r), child: Text(l10n.unfollow))
              : FilledButton(
                  key: Key('follow-${p.id}'),
                  onPressed: busy ? null : () => _toggleFollow(r),
                  child: Text(r.followsMe ? l10n.followBack : l10n.follow),
                ),
    );
  }

  Widget _body() {
    final l10n = context.l10n;
    final me = AuthScope.of(context).user?.uid;
    if (!_api.isConfigured) return const ServerNotConnectedView();

    if (_query.length < SearchPeoplePage.minChars) {
      final children = <Widget>[
        Padding(padding: const EdgeInsets.all(16), child: Text(l10n.searchPeopleMinChars)),
      ];
      if (_suggestionsError != null) {
        children.add(ListTile(
          title: Text(apiErrorText(context, _suggestionsError)),
          trailing: TextButton(key: const Key('suggestions-retry'), onPressed: _loadSuggestions, child: Text(l10n.retry)),
        ));
      } else if (_suggestions != null && _suggestions!.isNotEmpty) {
        children
          ..add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l10n.suggestionsTitle, style: Theme.of(context).textTheme.titleMedium),
          ))
          ..addAll(_suggestions!.map((r) => _row(r, isMe: r.person.id == me)));
      }
      return ListView(key: const Key('people-suggestions'), children: children);
    }
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: apiErrorText(context, _error), onRetry: () => _search(_query));
    if (_results.isEmpty) return EmptyView(message: l10n.searchPeopleEmpty);
    return ListView.builder(
      key: const Key('people-results'),
      itemCount: _results.length + (_cursor != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _results.length) {
          return Center(
            child: _loadingMore
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                : TextButton(key: const Key('people-load-more'), onPressed: _loadMore, child: Text(l10n.loadMore)),
          );
        }
        final r = _results[i];
        return _row(r, isMe: r.person.id == me);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('people-search-input'),
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            _search(v.trim());
          },
          decoration: InputDecoration(hintText: l10n.searchPeopleHint, border: InputBorder.none),
        ),
      ),
      body: _body(),
    );
  }
}
