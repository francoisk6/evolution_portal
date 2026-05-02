import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_info_provider.dart';
import '../../state/version_provider.dart';
import '../../widgets/error_message.dart';
import '../../widgets/grid_scroll_container.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  Widget _kv(BuildContext context, String k, String v) {
    final t = Theme.of(context).textTheme;

    final keyText = Text(
      k,
      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    final valueText = Text(
      v,
      style: t.bodyMedium,
      textAlign: TextAlign.right,
      softWrap: true,
    );

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 420;
        if (narrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                keyText,
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(v, style: t.bodyMedium, softWrap: true),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(child: keyText),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: valueText,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kvW(BuildContext context, String k, Widget v) {
    final t = Theme.of(context).textTheme;

    final keyText = Text(
      k,
      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 420;
        if (narrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                keyText,
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: v),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(child: keyText),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: v,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(versionInfoProvider);
    final appAsync = ref.watch(appVersionProvider);

    return GridScrollContainer(
      child: LayoutBuilder(
        builder: (context, c) {
          final isMobile = c.maxWidth < 720;

          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ABOUT',
                // Match the same page heading style used on the Brands page.
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.apps_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Application',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      _kvW(
                        context,
                        'App Version',
                        appAsync.when(
                          loading: () => const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (_, __) => Text(
                            '—',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          data: (v) => Text(
                            v,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      _kv(context, 'Powered by', 'AndyQueen'),
                      _kv(
                        context,
                        'Developed by',
                        'Francois Kassis (+96170238494)',
                      ),
                      _kv(context, 'Owner', 'Evolution Portal'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Backend Versions',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh',
                            icon: const Icon(Icons.refresh),
                            onPressed: () =>
                                ref.invalidate(versionInfoProvider),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      async.when(
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ErrorMessage(
                            message: e
                                .toString()
                                .replaceFirst('Exception:', '')
                                .trim(),
                          ),
                        ),
                        data: (v) => Column(
                          children: [
                            _kv(context, 'API Version', v.apiVersion),
                            _kv(context, 'GUI Version', v.guiVersion),
                            _kv(context, 'Web Version', v.webVersion),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

          if (isMobile) return body;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: body,
            ),
          );
        },
      ),
    );
  }
}
