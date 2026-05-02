import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/session_provider.dart';
import '../../services/auth_service.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _pass2Ctl = TextEditingController();
  final _firstCtl = TextEditingController();
  final _lastCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    _pass2Ctl.dispose();
    _firstCtl.dispose();
    _lastCtl.dispose();
    super.dispose();
  }

  Future<void> _doRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.register(
        username: _usernameCtl.text.trim(),
        email: _emailCtl.text.trim(),
        password: _passCtl.text,
        password2: _pass2Ctl.text,
        firstName: _firstCtl.text.trim().isEmpty ? null : _firstCtl.text.trim(),
        lastName: _lastCtl.text.trim().isEmpty ? null : _lastCtl.text.trim(),
      );
      if (!mounted) return; // <- important guard
      await ref.read(sessionProvider).setLoggedIn(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Create Account',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
        ],
        Form(
          key: _formKey,
          child: Column(children: [
            TextFormField(
              controller: _usernameCtl,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtl,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pass2Ctl,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              obscureText: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v != _passCtl.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstCtl,
              decoration:
                  const InputDecoration(labelText: 'First name (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastCtl,
              decoration:
                  const InputDecoration(labelText: 'Last name (optional)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _doRegister,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Register'),
            ),
          ]),
        ),
      ],
    );
  }
}
