import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app_env.dart';
import 'app/app_router.dart';
import 'app/app_scroll_behavior.dart';
import 'app/app_theme.dart';
import 'app/app_state_scope.dart';
import 'features/update/force_update_gate.dart';
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

  runApp(
    AppStateScope(
      key: appStateScopeKey,
      child: const EvolutionApp(),
    ),
  );
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
              ],
            );
          },
        );
      },
    );
  }
}
