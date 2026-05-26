import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app_env.dart';
import 'app/app_router.dart';
import 'app/app_scroll_behavior.dart';
import 'app/app_theme.dart';
import 'app/app_state_scope.dart';
import 'features/update/force_update_gate.dart';
import 'features/update/maintenance_gate.dart';
import 'state/session_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEnv.initWorkspace();
  // Pre-warm the SharedPreferences singleton so SessionState._bootstrap()
  // gets a cached instance and completes before the first frame renders,
  // eliminating the auth-state race on cold start.
  await SharedPreferences.getInstance();

  assert(() {
    debugPrintGlobalKeyedWidgetLifecycle = true;
    return true;
  }());

  // Replace the release-mode default ErrorWidget (an invisible Container) so
  // build-time failures show a visible message + recovery action instead of
  // a blank/grey body that also appears unresponsive to navigation.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Also print to console so the full trace is visible in browser DevTools.
    FlutterError.dumpErrorToConsole(details, forceReport: true);
    return _BuildFailureFallback(details: details);
  };

  runApp(
    AppStateScope(
      key: appStateScopeKey,
      child: const EvolutionApp(),
    ),
  );
}

class _BuildFailureFallback extends StatelessWidget {
  final FlutterErrorDetails details;
  const _BuildFailureFallback({required this.details});

  String get _briefError {
    final msg = details.exception.toString();
    const max = 160;
    return msg.length <= max ? msg : '${msg.substring(0, max)}…';
  }

  // Returns the first few stack frames from our own package code.
  String get _briefLocation {
    final trace = details.stack?.toString() ?? '';
    final frames = <String>[];
    for (final line in trace.split('\n')) {
      if (frames.length >= 4) break;
      final t = line.trim();
      if (t.contains('package:evolution_portal/') ||
          t.contains('evolution_portal/lib/')) {
        final match = RegExp(r'\((.*?:\d+(?::\d+)?)\)').firstMatch(t);
        frames.add(match != null ? match.group(1)! : (t.length > 100 ? '${t.substring(0, 100)}…' : t));
      }
    }
    return frames.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF8F8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 36),
              const SizedBox(height: 8),
              const Text(
                'Something went wrong loading this page.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              // Error detail — helps diagnose which widget/provider threw.
              Text(
                _briefError,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontFamily: 'monospace',
                ),
              ),
              if (_briefLocation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _briefLocation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black38,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      try {
                        GoRouter.of(context).go('/home');
                      } catch (_) {
                        AppStateScope.reset();
                      }
                    },
                    icon: const Icon(Icons.home),
                    label: const Text('Go Home'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => AppStateScope.reset(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset App'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EvolutionApp extends ConsumerWidget {
  const EvolutionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Evolution Portal',
      debugShowCheckedModeBanner: false,
      theme: buildV2LightTheme(),
      scrollBehavior: const EvolutionScrollBehavior(showScrollbars: true),
      routerConfig: router,
      builder: (context, child) {
        // Consumer is scoped here so only the overlay stack rebuilds when
        // session.ready changes — MaterialApp.router itself does NOT rebuild,
        // which prevents a double-rebuild conflict with GoRouter's
        // refreshListenable firing at the same time.
        return Consumer(
          builder: (context, ref, _) {
            final sessionReady =
                ref.watch(sessionProvider.select((s) => s.ready));
            return Stack(
              children: [
                if (child != null) child,
                if (!sessionReady)
                  // Opaque cover while bootstrap runs, prevents white flash
                  // before the router knows the correct auth destination.
                  SizedBox.expand(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                const ForceUpdateGate(),
                const MaintenanceGate(),
              ],
            );
          },
        );
      },
    );
  }
}
