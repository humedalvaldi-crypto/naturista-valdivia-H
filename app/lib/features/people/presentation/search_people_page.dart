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

/// Pantalla completa del buscador de personas.
class SearchPeoplePage extends StatelessWidget {
  const SearchPeoplePage({super.key});

  static const minChars = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.searchPeopleTitle)),
      body: const PeopleSearchView(autofocus: true),
    );
  }
}

/// Buscador de personas: resultados reales del servidor, paginados. Sin texto
/// muestra sugerencias de tu red y el directorio completo (también paginado).
class PeopleSearchView extends StatefulWidget {
  const PeopleSearchView({super.key, this.autofocus = false});

  final bool autofocus;

  @override
  State<PeopleSearchView> createState() => _PeopleSearchViewState();
}

class _PeopleSearchViewState extends State<PeopleSearchView> {
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
    if (!_suggestionsRequested && _api.isConfigured) {
      _suggestionsRequested = true;
      final signedIn = AuthScope.read(context).isSignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (signedIn) _loadSuggestions();
        _search('');
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
    if (q.isNotEmpty && q.length < SearchPeoplePage.minChars) {
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

  Widget _row(PersonResult r, {required bool isMe, String keyPrefix = 'person-result'}) {
    final l10n = context.l10n;
    final p = r.person;
    final chips = [
      if (r.followers != null) l10n.followers(r.followers!),
      if (r.followsMe) l10n.followsYou,
      if (r.mutuals != null && r.mutuals! > 0) l10n.mutualsCount(r.mutuals!),
    ];
    final busy = _busy.contains(p.id);
    return ListTile(
      key: Key('$keyPrefix-${p.id}'),
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

    if (_query.isNotEmpty && _query.length < SearchPeoplePage.minChars) {
      return ListView(children: [Padding(padding: const EdgeInsets.all(16), child: Text(l10n.searchPeopleMinChars))]);
    }
    final header = <Widget>[];
    if (_query.isEmpty) {
      if (_suggestionsError != null) {
        header.add(ListTile(
          title: Text(apiErrorText(context, _suggestionsError)),
          trailing: TextButton(key: const Key('suggestions-retry'), onPressed: _loadSuggestions, child: Text(l10n.retry)),
        ));
      } else if (_suggestions != null && _suggestions!.isNotEmpty) {
        header
          ..add(_sectionTitle(l10n.suggestionsTitle))
          ..addAll(_suggestions!.map((r) => _row(r, isMe: r.person.id == me, keyPrefix: 'suggestion')));
      }
      header.add(_sectionTitle(l10n.peopleDirectoryTitle));
    }
    if (_loading && header.isEmpty) return const LoadingView();
    if (_error != null && header.isEmpty) return ErrorView(message: apiErrorText(context, _error), onRetry: () => _search(_query));
    if (_results.isEmpty && !_loading && _error == null && header.isEmpty) return EmptyView(message: l10n.searchPeopleEmpty);
    final tail = <Widget>[
      if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (_error != null)
        ListTile(
          title: Text(apiErrorText(context, _error)),
          trailing: TextButton(onPressed: () => _search(_query), child: Text(l10n.retry)),
        ),
      if (!_loading && _error == null && _results.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(l10n.searchPeopleEmpty)),
    ];
    final results = _loading || _error != null ? const <PersonResult>[] : _results;
    return ListView.builder(
      key: Key(_query.isEmpty ? 'people-suggestions' : 'people-results'),
      itemCount: header.length + results.length + tail.length + (_cursor != null && !_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        var i = index - header.length;
        if (i < results.length) {
          final r = results[i];
          return _row(r, isMe: r.person.id == me);
        }
        i -= results.length;
        if (i < tail.length) return tail[i];
        return Center(
          child: _loadingMore
              ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
              : TextButton(key: const Key('people-load-more'), onPressed: _loadMore, child: Text(l10n.loadMore)),
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            key: const Key('people-search-input'),
            controller: _input,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) {
              _debounce?.cancel();
              _search(v.trim());
            },
            decoration: InputDecoration(
              hintText: l10n.searchPeopleHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }
}
