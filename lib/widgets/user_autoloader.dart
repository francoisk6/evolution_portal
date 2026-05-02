import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../state/session_provider.dart';

class UserAutoLoader extends ConsumerStatefulWidget {
  const UserAutoLoader({super.key});
  @override
  ConsumerState<UserAutoLoader> createState() => _UserAutoLoaderState();
}

class _UserAutoLoaderState extends ConsumerState<UserAutoLoader> {
  bool _ran = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ran) return;
    _ran = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await AuthService.instance.me();
      if (!mounted) return; // <- important guard
      String? avatar;
      final profile = me['profile'];
      if (profile is Map<String, dynamic>) {
        avatar = (profile['avatar'] ??
                profile['avatar_url'] ??
                profile['profile_image'])
            ?.toString();
      }
      avatar ??=
          (me['avatar'] ?? me['avatar_url'] ?? me['profile_image'])?.toString();
      if (avatar != null && avatar.isNotEmpty) {
        ref.read(sessionProvider).setAvatarUrl(avatar);
      }
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
