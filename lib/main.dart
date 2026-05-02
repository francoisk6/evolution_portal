import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app_env.dart';
import 'app/app_router.dart';
import 'app/app_scroll_behavior.dart';
import 'app/app_theme.dart';
import 'app/app_state_scope.dart';
import 'features/update/force_update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEnv.initWorkspace();

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
        return Stack(
          children: [
            if (child != null) child,
            const ForceUpdateGate(),
          ],
        );
      },
    );
  }
}
