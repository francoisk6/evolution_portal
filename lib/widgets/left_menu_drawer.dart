import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/app_env.dart';
import '../data/models/catalog_update.dart';
import '../routing/route_names.dart';
import '../state/app_info_provider.dart';
import '../state/catalog_update_provider.dart';
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
                        if (session.isSuperuser)
                          ExpansionTile(
                            leading: const Icon(Icons.cloud_sync_outlined),
                            title: const Text('Update Catalog'),
                            childrenPadding: const EdgeInsets.only(left: 16),
                            children: [
                              for (final target in kCatalogTargets)
                                _CatalogUpdateTile(target: target),
                            ],
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

/// A single catalog-update entry. Tapping fires the job and leaves the drawer
/// open, so progress and the result stay visible; run state lives in
/// [catalogUpdateProvider] so it also survives the drawer being closed.
class _CatalogUpdateTile extends ConsumerWidget {
  final CatalogTarget target;

  const _CatalogUpdateTile({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(catalogUpdateProvider).stateFor(target.key);
    final scheme = Theme.of(context).colorScheme;

    Widget? trailing;
    switch (run.status) {
      case CatalogRunStatus.running:
        trailing = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case CatalogRunStatus.success:
        trailing =
            Icon(Icons.check_circle_outline, size: 20, color: scheme.primary);
        break;
      case CatalogRunStatus.failure:
        trailing = Icon(Icons.error_outline, size: 20, color: scheme.error);
        break;
      case CatalogRunStatus.idle:
        trailing = null;
        break;
    }

    return ListTile(
      leading: Icon(target.icon),
      title: Text(target.label),
      subtitle: run.message == null
          ? null
          : Text(
              run.elapsed == null
                  ? run.message!
                  : '${run.message!} · ${_formatElapsed(run.elapsed!)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: run.status == CatalogRunStatus.failure
                    ? scheme.error
                    : null,
              ),
            ),
      trailing: trailing,
      enabled: !run.isRunning,
      onTap: run.isRunning
          ? null
          : () => ref.read(catalogUpdateProvider.notifier).run(target),
    );
  }
}

String _formatElapsed(Duration d) {
  final seconds = d.inMilliseconds / 1000.0;
  return '${seconds.toStringAsFixed(1)}s';
}
