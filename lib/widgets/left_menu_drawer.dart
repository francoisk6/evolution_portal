import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/app_env.dart';
import '../routing/route_names.dart';
import '../state/app_info_provider.dart';
import '../state/session_provider.dart';

class LeftMenuDrawer extends ConsumerWidget {
  const LeftMenuDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    bool isRoute(String route) => location.startsWith(route);

    final appAsync = ref.watch(appVersionProvider);
    final session = ref.watch(sessionProvider);
    final showMainSuperuserTools = session.isSuperuser &&
        AppEnv.selectedWorkspace.slug == AppEnv.defaultWorkspace.slug;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Home'),
                    selected: isRoute(R.home),
                    onTap: () {
                      context.go(R.home);
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                  ExpansionTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: const Text('Account'),
                    initiallyExpanded: location.startsWith('/account'),
                    childrenPadding: const EdgeInsets.only(left: 16),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: const Text('Transaction History'),
                        selected: isRoute(R.transactions),
                        onTap: () {
                          context.go(R.transactions);
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.balance),
                        title: const Text('Balance History'),
                        selected: isRoute(R.accountBalanceHistory),
                        onTap: () {
                          context.go(R.accountBalanceHistory);
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.space_dashboard_outlined),
                        title: const Text('My Dashboard'),
                        selected: isRoute(R.accountMyDashboard),
                        onTap: () {
                          context.go(R.accountMyDashboard);
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Profile'),
                        selected: isRoute(R.accountProfile),
                        onTap: () {
                          context.go(R.accountProfile);
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.batch_prediction_outlined),
                        title: const Text('Batch Refill'),
                        selected: isRoute(R.adminBatchRefill),
                        onTap: () {
                          context.go(R.adminBatchRefill);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  if (session.isAdmin) ...[
                    ExpansionTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Admin'),
                      initiallyExpanded: location.startsWith('/admin'),
                      childrenPadding: const EdgeInsets.only(left: 16),
                      children: [
                        ListTile(
                          leading: const Icon(Icons.percent_outlined),
                          title: const Text('User X Brand profit'),
                          selected: isRoute(R.adminUserBrandProfit),
                          onTap: () {
                            context.go(R.adminUserBrandProfit);
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: const Text('Prepaid cards stock'),
                          selected: isRoute(R.adminPrepaidStock),
                          onTap: () {
                            context.go(R.adminPrepaidStock);
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.hub_outlined),
                          title: const Text('Workspace Ops'),
                          selected: isRoute(R.adminWorkspaceOps),
                          onTap: () {
                            context.go(R.adminWorkspaceOps);
                            Navigator.pop(context);
                          },
                        ),
                        if (showMainSuperuserTools)
                          ListTile(
                            leading:
                                const Icon(Icons.cleaning_services_outlined),
                            title: const Text('Workspace Transaction Cleanup'),
                            selected:
                                isRoute(R.adminWorkspaceTransactionCleanup),
                            onTap: () {
                              context.go(R.adminWorkspaceTransactionCleanup);
                              Navigator.pop(context);
                            },
                          ),
                      ],
                    ),
                    const Divider(),
                  ],
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('About'),
                    selected: isRoute(R.about),
                    onTap: () {
                      context.go(R.about);
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '© 2026 Evolution Portal',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appAsync.when(
                      loading: () => 'App v…',
                      error: (_, __) => 'App v—',
                      data: (v) => 'App v$v',
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
