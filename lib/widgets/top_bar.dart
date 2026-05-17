import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../app/app_env.dart';
import '../routing/route_names.dart';
import '../state/session_provider.dart';
import '../services/auth_service.dart';
import '../app/app_cache_manager.dart';
import 'notification_bell.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  Uri _adminUri() {
    final base = Uri.parse(AppEnv.base);
    final segments = List<String>.from(base.pathSegments);
    if (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.isNotEmpty && segments.last == 'api') {
      segments.removeLast();
    }
    return base.replace(
      pathSegments: [...segments, 'admin'],
      query: null,
      fragment: null,
    );
  }

  Future<void> _openAdmin(BuildContext context) async {
    final uri = _adminUri();
    final opened = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open admin panel.')),
      );
    }
  }

  Widget _adminButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAdmin(context),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFD3FF), width: 2),
            color: Colors.white,
          ),
          child: const Center(
            child: Icon(Icons.admin_panel_settings_outlined, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final session = ref.watch(sessionProvider);

    ImageProvider? foreground;
    final url = session.avatarUrl;
    if (url != null && url.isNotEmpty) {
      foreground = CachedNetworkImageProvider(
        url,
        cacheManager: AppCacheManager.images,
      );
    }

    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
          tooltip: 'Menu',
        ),
      ),
      title: InkWell(
        onTap: () => context.go(R.home),
        child: Row(
          children: [
            Image.asset('assets/logo.png', height: 28),
          ],
        ),
      ),
      actions: [
        if (session.isAdmin) _adminButton(context),
        const NotificationBell(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: InkWell(
            onTap: () => context.go(R.accountProfile),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: const AssetImage('assets/logo.png'),
              foregroundImage: foreground,
              onForegroundImageError: foreground != null ? (_, __) {} : null,
            ),
          ),
        ),
        if (width > 420)
          TextButton.icon(
            onPressed: () async {
              await AuthService.instance.logout();
              await ref.read(sessionProvider).logout();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
          )
        else
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService.instance.logout();
              await ref.read(sessionProvider).logout();
            },
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}
