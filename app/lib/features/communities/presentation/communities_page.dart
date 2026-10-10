import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../social/data/social_api.dart';
import '../../social/domain/models.dart';

/// Comunidades temáticas: listar, unirse, salir y crear.
class CommunitiesPage extends StatefulWidget {
  const CommunitiesPage({super.key});

  @override
  State<CommunitiesPage> createState() => _CommunitiesPageState();
}

class _CommunitiesPageState extends State<CommunitiesPage> {
  late SocialApi _api;
  List<Community> _items = [];
  Object? _error;
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _api.isConfigured) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = SocialApi(ApiScope.of(context));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.communities();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(Community c) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AuthScope.read(context).isSignedIn) {
      context.go('/login?from=%2Fcommunities');
      return;
    }
    setState(() => _busy.add(c.slug));
    try {
      final updated = await _api.setMembership(c.slug, !c.isMember);
      if (mounted) setState(() => _items = [for (final i in _items) i.slug == c.slug ? updated : i]);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _busy.remove(c.slug));
    }
  }

  Future<void> _create() async {
    final created = await showDialog<Community>(context: context, builder: (_) => _CreateCommunityDialog(api: _api));
    if (created != null && mounted) setState(() => _items = [created, ..._items]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final signedIn = AuthScope.of(context).isSignedIn;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else if (_items.isEmpty) {
      body = EmptyView(message: l10n.communitiesEmpty);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final c = _items[i];
            final busy = _busy.contains(c.slug);
            return Card(
              key: Key('community-${c.slug}'),
              child: ListTile(
                leading: CircleAvatar(child: Text(c.name.characters.first.toUpperCase())),
                title: Text(c.name),
                subtitle: Text([
                  l10n.memberCount(c.memberCount),
                  if (c.wetland != null) c.wetland!,
                  if (c.description != null) c.description!,
                ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: c.myRole == 'owner'
                    ? null
                    : (c.isMember
                        ? OutlinedButton(onPressed: busy ? null : () => _toggle(c), child: Text(l10n.leave))
                        : FilledButton(onPressed: busy ? null : () => _toggle(c), child: Text(l10n.join))),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.communitiesTitle)),
      floatingActionButton: _api.isConfigured && signedIn
          ? FloatingActionButton.extended(
              key: const Key('create-community'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(l10n.createCommunity),
            )
          : null,
      body: body,
    );
  }
}

class _CreateCommunityDialog extends StatefulWidget {
  const _CreateCommunityDialog({required this.api});
  final SocialApi api;

  @override
  State<_CreateCommunityDialog> createState() => _CreateCommunityDialogState();
}

class _CreateCommunityDialogState extends State<_CreateCommunityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _description = TextEditingController();
  final _wetland = TextEditingController();
  bool _sending = false;
  String? _error;

  static final _slugPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$');

  @override
  void dispose() {
    for (final c in [_name, _slug, _description, _wetland]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final created = await widget.api.createCommunity(
        name: _name.text.trim(),
        slug: _slug.text.trim().toLowerCase(),
        description: _description.text,
        wetland: _wetland.text,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = apiErrorText(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    return AlertDialog(
      title: Text(l10n.createCommunity),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                TextFormField(
                  key: const Key('community-name'),
                  controller: _name,
                  decoration: InputDecoration(labelText: l10n.communityName),
                  validator: (v) => (v == null || v.trim().length < 3) ? l10n.errorRequired : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('community-slug'),
                  controller: _slug,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l10n.communitySlug),
                  validator: (v) => _slugPattern.hasMatch((v ?? '').trim().toLowerCase()) ? null : l10n.communitySlugError,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _wetland, decoration: InputDecoration(labelText: l10n.communityWetland)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: l10n.communityDescription),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          key: const Key('community-submit'),
          onPressed: _sending ? null : _submit,
          child: Text(l10n.create),
        ),
      ],
    );
  }
}
