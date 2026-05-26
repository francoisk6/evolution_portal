import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_env.dart';
import '../../app/app_state_scope.dart';
import '../../routing/route_names.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../state/session_provider.dart';
import 'models/saved_account.dart';
import 'services/accounts_store.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _accountsStore = AccountsStore();

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _rememberAccount = true;

  List<SavedAccount> _accounts = [];
  WorkspaceConfig _workspace = AppEnv.selectedWorkspace;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final items = await _accountsStore.listAccounts();
    if (!mounted) return;
    setState(() => _accounts = items);
  }

  String _cleanError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }

  SavedAccount _accountFromMe(Map<String, dynamic> me, {String? fallbackUsername}) {
    final profile = (me['profile'] is Map<String, dynamic>)
        ? me['profile'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return SavedAccount(
      id: (me['id'] as num?)?.toInt() ?? 0,
      username: (me['username'] as String?) ?? (fallbackUsername ?? ''),
      email: (me['email'] as String?) ?? '',
      firstName: (me['first_name'] as String?) ?? '',
      lastName: (me['last_name'] as String?) ?? '',
      avatarUrl: (profile['avatar'] as String?) ?? '',
      lastUsedAt: DateTime.now(),
    );
  }

  Future<void> _continueWithAccount(SavedAccount acc) async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final token = await _accountsStore.readToken(acc.username);
      if (token == null || token.isEmpty) {
        throw Exception('No token saved for this account. Please sign in again.');
      }

      // Make this token the active session.
      await ApiService.instance.setAuthToken(token);

      // Refresh profile from backend for correctness.
      final me = await AuthService.instance.me();

      // Persist same keys used elsewhere in the app.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_json', jsonEncode(me));

      // Reset all providers so home page builds with clean state (no stale
      // provider data from the previous session causing a null crash).
      await ref.read(sessionProvider).persistLoginDataForReset(me);
      AppStateScope.reset();

      // Refresh the cached account card.
      final updated = _accountFromMe(me, fallbackUsername: acc.username);
      await _accountsStore.upsertAccount(updated);
      await _accountsStore.setActiveUsername(updated.username);
    } catch (e) {
      if (mounted) setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeAccount(SavedAccount acc) async {
    await _accountsStore.removeAccount(acc.username);
    await _loadAccounts();
  }

  Future<void> _changeWorkspace() async {
    if (AppEnv.isWebHostWorkspaceLocked) return;

    final selected = await showDialog<WorkspaceConfig>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Change Workspace"),
        children: [
          for (final workspace in AppEnv.workspaces)
            RadioListTile<String>(
              value: workspace.slug,
              groupValue: _workspace.slug,
              title: Text(workspace.displayName),
              subtitle: Text(workspace.apiBaseUrl),
              onChanged: (_) => Navigator.of(ctx).pop(workspace),
            ),
        ],
      ),
    );

    if (selected == null || selected.slug == _workspace.slug) return;

    await AppEnv.selectWorkspace(selected.slug);
    await ApiService.instance.setAuthToken(null);
    if (!mounted) return;
    setState(() {
      _workspace = AppEnv.selectedWorkspace;
      _error = null;
    });
    await _loadAccounts();
  }

  Future<void> _loginAndSave() async {
    final u = _username.text.trim();
    final p = _password.text;
    final pin = _pin.text.trim();

    if (u.isEmpty || p.isEmpty || pin.length != 4) {
      setState(() => _error = 'Please enter username, password, and a 4-digit PIN.');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      // This will also persist SharedPreferences('auth_token') via ApiService.
      final me = await AuthService.instance.login(u, p, pin);

      // Reset all providers so home page builds with clean state (no stale
      // provider data from the previous session causing a null crash).
      await ref.read(sessionProvider).persistLoginDataForReset(me);
      AppStateScope.reset();

      // Save for quick account switching (token + profile). Token comes from the login response.
      // Token may be returned either inside {data.token} or at envelope level.
      // ApiService always persists SharedPreferences('auth_token') on successful login,
      // so read from there to avoid API-shape differences.
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? (me['token'] as String?) ?? '';
      if (_rememberAccount && token.isNotEmpty) {
        final acc = _accountFromMe(me, fallbackUsername: u);
        await _accountsStore.upsertAccount(acc);
        await _accountsStore.writeToken(acc.username, token);
        await _accountsStore.setActiveUsername(acc.username);
        if (!mounted) return;
        await _loadAccounts();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _isLoading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(
                onPressed: () => context.go(R.register),
                child: const Text('Create account'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Workspace: ${_workspace.displayName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!AppEnv.isWebHostWorkspaceLocked)
                    TextButton(
                      onPressed: _changeWorkspace,
                      child: const Text('Change Workspace'),
                    ),
                ],
              ),
            ),
          ),

          if (_accounts.isNotEmpty) ...[
            const Text(
              'Saved accounts',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._accounts.map(
              (acc) => _AccountTile(
                account: acc,
                onContinue: () => _continueWithAccount(acc),
                onRemove: () => _removeAccount(acc),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
          ],

          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 10),
          ],

          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _username,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(labelText: 'PIN (4 digits)'),
                  onSubmitted: (_) => _loginAndSave(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Switch(
                value: _rememberAccount,
                onChanged: (v) => setState(() => _rememberAccount = v),
              ),
              const SizedBox(width: 6),
              const Expanded(child: Text('Remember this account on this device')),
            ],
          ),

          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _loginAndSave,
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final SavedAccount account;
  final VoidCallback onContinue;
  final VoidCallback onRemove;

  const _AccountTile({
    required this.account,
    required this.onContinue,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final rawAvatar = account.avatarUrl.trim();
    final avatar = rawAvatar.startsWith('http:')
        ? rawAvatar.replaceFirst('http:', 'https:')
        : rawAvatar;

    // On smaller screens, trailing actions can consume most of the width and
    // force the title/subtitle into an unusably narrow column. For compact
    // layouts, make the tile itself tappable (Continue) and keep only a menu.
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 420;

    return Card(
      child: ListTile(
        onTap: onContinue,
        dense: compact,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 2 : 4),
        minLeadingWidth: compact ? 40 : 0,
        horizontalTitleGap: compact ? 10 : 16,
        leading: CircleAvatar(
          radius: compact ? 18 : 20,
          backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
          child: avatar.isEmpty
              ? Text(account.username.isNotEmpty ? account.username[0] : '?')
              : null,
        ),
        title: Text(
          account.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          account.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: compact
            ? PopupMenuButton<int>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 1) onRemove();
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem<int>(
                    value: 1,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Remove'),
                      ],
                    ),
                  ),
                ],
              )
            : Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: onContinue, child: const Text('Continue')),
                  IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
                ],
              ),
      ),
    );
  }
}
