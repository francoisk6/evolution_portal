import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/models/notification_models.dart';
import '../routing/route_names.dart';
import '../state/notification_provider.dart';
import '../state/session_provider.dart';
import '../utils/notify.dart';

class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (!session.loggedIn) return;
      ref.read(notificationCenterProvider.notifier).refreshUnreadCount();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (!session.loggedIn) return;
      ref.read(notificationCenterProvider.notifier).pollLatestUnread();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPanel() async {
    unawaited(
      ref.read(notificationCenterProvider.notifier).refreshAll(resetList: true),
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.black12,
      pageBuilder: (dialogContext, _, __) {
        final width = MediaQuery.of(dialogContext).size.width;
        final panelWidth = math.min(380.0, width - 16);
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 70, right: 8, left: 8),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: panelWidth,
                  child: _NotificationsPanel(
                    onClose: () => Navigator.of(dialogContext).pop(),
                    onNavigate: (item) async {
                      try {
                        if (!item.isRead) {
                          await ref
                              .read(notificationCenterProvider.notifier)
                              .markOneRead(item.id);
                        }
                        if (!dialogContext.mounted || !mounted) return;
                        Navigator.of(dialogContext).pop();
                        _goToNotificationUrl(item.url);
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        showCaughtError(dialogContext, e);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _goToNotificationUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return;

    if (url.contains('/account/balance-history/')) {
      context.go(R.accountBalanceHistory);
      return;
    }
    if (url.contains('/account/transactions/')) {
      context.go(R.transactions);
      return;
    }
    if (url.contains('/account/profile/')) {
      context.go(R.accountProfile);
      return;
    }
    if (url.contains('/account/my-dashboard/')) {
      context.go(R.accountMyDashboard);
      return;
    }
    if (url.contains('/purchase/')) {
      context.go(R.purchase);
      return;
    }
    context.go(R.home);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationCenterProvider);
    final unread = state.unreadCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openPanel,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFD3FF), width: 2),
            color: Colors.white,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(Icons.notifications_none, color: Colors.black87),
              ),
              if (unread > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    height: 18,
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsPanel extends ConsumerWidget {
  final VoidCallback onClose;
  final Future<void> Function(NotificationItem item) onNavigate;

  const _NotificationsPanel({
    required this.onClose,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationCenterProvider);
    final notifier = ref.read(notificationCenterProvider.notifier);

    final panelHeight = math.min(
      430.0,
      MediaQuery.of(context).size.height * 0.72,
    );

    return Container(
      height: panelHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8D8D8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: state.items.isEmpty && state.unreadCount == 0
                      ? null
                      : () async {
                          try {
                            await notifier.markAllRead();
                          } catch (e) {
                            if (!context.mounted) return;
                            showCaughtError(context, e);
                          }
                        },
                  child: const Text('Mark all read'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (state.loadingList && state.items.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.error != null && state.items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => notifier.loadFirstPage(limit: state.limit),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (state.items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No notifications yet.',
                          style: TextStyle(color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: onClose,
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.pixels >=
                            notification.metrics.maxScrollExtent - 80 &&
                        !state.loadingMore &&
                        state.hasMore) {
                      notifier.loadMore();
                    }
                    return false;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    itemCount: state.items.length + (state.loadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final item = state.items[index];
                      return _NotificationTile(
                        key: ValueKey(
                          'notification-${item.id}-${item.isRead}-${item.actions.length}',
                        ),
                        item: item,
                        isDeleteDisabled: item.actions.any(
                          (action) => notifier.isActionLoading(item.id, action.key),
                        ),
                        onTap: () => onNavigate(item),
                        onDelete: () async {
                          try {
                            await notifier.deleteOne(item.id);
                          } catch (e) {
                            if (!context.mounted) return;
                            showCaughtError(context, e);
                          }
                        },
                        onAction: (action) async {
                          try {
                            final confirmText = action.confirm.trim();
                            if (confirmText.isNotEmpty) {
                              final approved = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Confirm action'),
                                  content: Text(confirmText),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(dialogContext).pop(false),
                                      child: const Text('No'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(dialogContext).pop(true),
                                      child: const Text('Yes'),
                                    ),
                                  ],
                                ),
                              );
                              if (approved != true) return;
                            }

                            final message = await notifier.runAction(item, action);
                            if (!context.mounted) return;
                            if (message.trim().isNotEmpty) {
                              showSuccess(context, message);
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            showCaughtError(context, e);
                          }
                        },
                        isActionLoading: (actionKey) =>
                            notifier.isActionLoading(item.id, actionKey),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<void> Function(NotificationAction action) onAction;
  final bool Function(String actionKey) isActionLoading;
  final bool isDeleteDisabled;

  const _NotificationTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDelete,
    required this.onAction,
    required this.isActionLoading,
    required this.isDeleteDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    final createdAt = item.createdAt;
    final when = createdAt == null
        ? ''
        : DateFormat('M/d/yyyy,\nh:mm:ss a').format(createdAt.toLocal());
    final title = item.verb.trim().isEmpty ? 'Notification' : item.verb.trim();
    final body = item.description.trim().isEmpty
        ? 'No details available.'
        : item.description.trim();
    final hasActions = item.actions.isNotEmpty;
    final canOpen = item.url.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: unread ? const Color(0xFFF1EAD6) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Stack(
        children: [
          if (unread)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFB300),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: canOpen ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (when.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 1),
                            child: Text(
                              when,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF666666),
                                height: 1.15,
                              ),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          onPressed: isDeleteDisabled ? null : onDelete,
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.35,
                      ),
                    ),
                    if (hasActions) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.actions.map((action) {
                          final loading = isActionLoading(action.key);
                          final style = _resolveButtonStyle(action.style);
                          return FilledButton(
                            onPressed: loading ? null : () => onAction(action),
                            style: style,
                            child: loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(action.label.trim().isEmpty
                                    ? 'Action'
                                    : action.label.trim()),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _resolveButtonStyle(String rawStyle) {
    final style = rawStyle.trim().toLowerCase();
    Color background = const Color(0xFF1976D2);
    Color foreground = Colors.white;

    if (style == 'success') {
      background = const Color(0xFF2E7D32);
    } else if (style == 'danger' || style == 'error') {
      background = const Color(0xFFC62828);
    } else if (style == 'warning') {
      background = const Color(0xFFED6C02);
    } else if (style == 'secondary') {
      background = const Color(0xFF5F6368);
    }

    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
}
