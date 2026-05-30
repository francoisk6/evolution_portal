import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../routing/route_names.dart';
import '../state/session_provider.dart';
import '../layouts/auth_scaffold.dart';
import 'app_scaffold.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/home/home_page.dart';
import '../features/account/transaction_history_page.dart';
import '../features/account/balance_history_page.dart';
import '../features/account/my_dashboard_page.dart';
import '../features/account/profile_page.dart';
import '../features/purchase/purchase_page.dart';
import '../features/online/online_brand_selection_page.dart';
import '../features/about/about_page.dart';
import '../features/admin/user_brand_profit_page.dart';
import '../features/admin/workspace_ops_page.dart';
import '../features/admin/workspace_transaction_cleanup_page.dart';
import '../features/admin/admin_webview_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // IMPORTANT: don't watch here — keeps a single router instance.
  final session = ref.read(sessionProvider);

  // Keys must live inside the provider so each ProviderScope reset (AppStateScope.reset)
  // gets fresh instances. Module-level singletons caused Flutter to transplant the old
  // Navigator element from inactive → new tree, then fail the _elements.contains assertion
  // when unmounting the old tree.
  final rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');
  final shellNavKey = GlobalKey<NavigatorState>(debugLabel: 'shellNav');

  return GoRouter(
    navigatorKey: rootNavKey,
    initialLocation: R.home,
    redirect: (context, state) {
      if (!session.ready) return null;
      final path = state.uri.path;
      final loggingIn = path == R.login || path == R.register;
      if (!session.loggedIn && !loggingIn) return R.login;
      if (session.loggedIn && loggingIn) return R.home;
      // Root path has no route — redirect to the correct destination.
      if (path == '/' || path.isEmpty) return session.loggedIn ? R.home : R.login;
      return null;
    },
    refreshListenable:
        session, // ✅ reacts to auth changes without recreating router
    // Any unmatched route (e.g. stale Android intent, deep link from an older
    // app version) silently routes to home/login instead of rendering blank.
    errorBuilder: (context, state) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = session.loggedIn ? R.home : R.login;
        context.go(target);
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    },
    routes: [
      GoRoute(
        path: R.login,
        builder: (context, state) => const AuthScaffold(child: LoginPage()),
      ),
      GoRoute(
        path: R.register,
        builder: (context, state) => const AuthScaffold(child: RegisterPage()),
      ),
      ShellRoute(
        navigatorKey: shellNavKey,
        builder: (context, state, child) =>
            AppScaffold(body: child, location: state.uri.toString()),
        routes: [
          GoRoute(path: R.home, builder: (c, s) => const HomePage()),
          GoRoute(path: R.about, builder: (c, s) => const AboutPage()),
          GoRoute(
              path: R.transactions,
              builder: (c, s) => const TransactionHistoryPage()),
          GoRoute(
            path: '${R.onlineBrands}/:groupDetailId',
            builder: (c, s) {
              final id =
                  int.tryParse(s.pathParameters['groupDetailId'] ?? '') ?? 0;
              final gsd = int.tryParse(s.uri.queryParameters['gsd'] ?? '');
              final productKey = (s.uri.queryParameters['q'] ?? '').trim();
              final searchMode = (s.uri.queryParameters['search'] ?? '').trim();

              return OnlineBrandSelectionPage(
                groupDetailId: id,
                initialGsd: gsd,
                productKey: productKey.isEmpty ? null : productKey,
                searchMode: searchMode.isEmpty ? null : searchMode,
              );
            },
          ),
          GoRoute(path: R.purchase, builder: (c, s) => const PurchasePage()),
          GoRoute(
              path: R.accountBalanceHistory,
              builder: (c, s) => const BalanceHistoryPage()),
          GoRoute(
              path: R.accountMyDashboard,
              builder: (c, s) => const MyDashboardPage()),
          GoRoute(
              path: R.accountProfile, builder: (c, s) => const ProfilePage()),
          GoRoute(
              path: R.adminUserBrandProfit,
              builder: (c, s) => const UserBrandProfitPage()),
          GoRoute(
              path: R.adminWorkspaceOps,
              builder: (c, s) => const WorkspaceOpsPage()),
          GoRoute(
              path: R.adminWorkspaceTransactionCleanup,
              builder: (c, s) => const WorkspaceTransactionCleanupPage()),
        ],
      ),
      // Admin WebView — outside ShellRoute so it gets its own AppBar with no BottomNav
      GoRoute(
        path: R.adminPanel,
        builder: (c, s) => const AdminWebViewScreen(),
      ),
    ],
  );
});
