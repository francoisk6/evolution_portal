import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../widgets/grid_scroll_container.dart';
import '../../state/groups_provider.dart';
import '../../state/products_without_groups_provider.dart';
import '../../state/page_refresh_provider.dart';
import '../../state/online_brand_selection_provider.dart';
import '../../state/online_customer_info_provider.dart';
import '../../state/online_purchase_criteria_provider.dart';
import '../../state/online_flow_state_provider.dart';
import '../../routing/route_names.dart';
import '../../app/app_env.dart';
import '../../app/app_cache_manager.dart';
import '../../app/app_scroll_behavior.dart';
import '../../widgets/history_text_field.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _qCtl = TextEditingController();
  final _pageScrollController = ScrollController();

  String get _q => _qCtl.text.trim();

  // Prevent repeated pre-cache attempts across rebuilds.
  final Set<String> _precachedIconUrls = <String>{};

  // One horizontal controller per section (for smooth scroll + scrollbar)
  final Map<int, ScrollController> _hCtrls = {};
  ScrollController _ctrlFor(int sectionId) =>
      _hCtrls.putIfAbsent(sectionId, () => ScrollController());

  String _mediaUrl(String avatar) {
    // API returns "/media/..." → make absolute using base (…/api/ → /)
    final root = AppEnv.base.replaceFirst(RegExp(r'/api/?$'), '/');
    if (avatar.startsWith('http')) {
      return avatar.startsWith('https') ? avatar : avatar.replaceFirst('http:', 'https:');
    }
    return '$root${avatar.replaceFirst(RegExp(r'^/'), '')}';
  }

  void _precacheSectionIcons(BuildContext context, List<HomeSection> sections) {
    for (final sec in sections) {
      for (final d in sec.details) {
        final url = _mediaUrl(d.avatar);
        if (url.isEmpty) continue;
        if (!_precachedIconUrls.add(url)) continue;

        precacheImage(
          CachedNetworkImageProvider(
            url,
            cacheManager: AppCacheManager.images,
          ),
          context,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _qCtl.addListener(() {
      if (!mounted) return;
      setState(() {}); // live filter as user types
    });

    // Load sections on first frame (no extra fetch if already loaded)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(onlineFlowProvider.notifier).resetAll();
      ref.read(onlineBrandSelectionProvider.notifier).state = null;
      ref.read(onlinePurchaseCriteriaProvider.notifier).state = null;
      ref.read(onlineCustomerInfoProvider.notifier).state = null;
      ref.read(groupsProvider.notifier).refresh(force: false);
      ref.read(productsWithoutGroupsProvider.notifier).refresh(force: false);
    });
  }

  @override
  void dispose() {
    _qCtl.dispose();
    _pageScrollController.dispose();
    for (final c in _hCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(pageRefreshPulseProvider, (prev, next) {
      if (prev == next) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent != true) return;
      // Refresh Home sections
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(groupsProvider.notifier).refresh(force: true);
        ref.read(productsWithoutGroupsProvider.notifier).refresh(force: true);
      });
    });

    final async = ref.watch(groupsProvider);
    final productsAsync = ref.watch(productsWithoutGroupsProvider);

    return ScrollConfiguration(
        // Keep horizontal section rows clean while forcing a visible vertical
        // scrollbar for the main Home page content.
        behavior: const EvolutionScrollBehavior(showScrollbars: false),
        child: GridScrollContainer(
          controller: _pageScrollController,
          showScrollbar: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== Search row (visual only for now) =====
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: HistoryTextField(
                        historyKey: 'home.product_search',
                        controller: _qCtl,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search products…',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: FilledButton(
                        onPressed: _qCtl.text.isEmpty
                            ? null
                            : () {
                                _qCtl.clear();
                                FocusScope.of(context).unfocus();
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        child: const Text('Clear'),
                      ),
                    ),
                  ],
                ),
              ),

              // ===== Sections =====
              async.when(
                loading: () => const _Skeleton(),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    e.toString().replaceFirst('Exception: ', ''),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                data: (sections) {
                  if (sections.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: Text('No sections available.')),
                    );
                  }

                  final q = _q;
                  final filteredSections = _filterSections(sections, q);

                  if (q.isNotEmpty && filteredSections.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: Text('No matches.')),
                          if (q.length >= 3)
                            _ProductsWithoutGroupsSection(
                              query: q,
                              productsAsync: productsAsync,
                            ),
                        ],
                      ),
                    );
                  }

                  // Smooth first render/scroll on mobile by pre-caching section icons.
                  _precacheSectionIcons(context, filteredSections);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredSections.length,
                        itemBuilder: (ctx, i) {
                          final sec = filteredSections[i];
                          final isLast = i == filteredSections.length - 1;
                          final hCtrl = _ctrlFor(sec.id);

                          return Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: IntrinsicHeight(
                                  child: Row(
                                    // Ensure left rail spans row height -> true vertical centering
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Vertical category label (left rail)
                                      SizedBox(
                                        width: 44,
                                        child: Center(
                                          child: RotatedBox(
                                            quarterTurns: 3,
                                            child: Text(
                                              sec.name.toUpperCase(),
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    letterSpacing: 1.2,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                      ..withValues(alpha: .65),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // One-line horizontal scroller with cards
                                      Expanded(
                                        child: SingleChildScrollView(
                                          controller: hCtrl,
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: Row(
                                            children: sec.details.map((d) {
                                              final avatar =
                                                  _mediaUrl(d.avatar);
                                              return Padding(
                                                key: ValueKey(d.id),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                                child: _GroupCard(
                                                  title: d.name,
                                                  imageUrl: avatar,
                                                  onTap: () {
                                                    context.go(
                                                      '${R.onlineBrands}/${d.id}',
                                                    );
                                                  },
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isLast) const Divider(height: 16),
                            ],
                          );
                        },
                      ),
                      if (q.length >= 3)
                        _ProductsWithoutGroupsSection(
                          query: q,
                          productsAsync: productsAsync,
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ));
  }

  List<HomeSection> _filterSections(List<HomeSection> sections, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return sections;

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return sections;

    bool matches(String haystack) {
      final h = haystack.toLowerCase();
      return tokens.every(h.contains);
    }

    final out = <HomeSection>[];
    for (final sec in sections) {
      final details = sec.details.where((d) {
        final hay = '${sec.name} ${d.name} ${d.search}'.trim();
        return matches(hay);
      }).toList(growable: false);

      if (details.isEmpty) continue;
      out.add(HomeSection(id: sec.id, name: sec.name, details: details));
    }
    return out;
  }
}

class _ProductsWithoutGroupsSection extends StatelessWidget {
  final String query;
  final AsyncValue<List<ProductWithoutGroup>> productsAsync;

  const _ProductsWithoutGroupsSection({
    required this.query,
    required this.productsAsync,
  });

  List<ProductWithoutGroup> _filterProducts(
      List<ProductWithoutGroup> products) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];

    bool matches(String haystack) {
      final h = haystack.toLowerCase();
      return tokens.every(h.contains);
    }

    return products.where((p) {
      final hay = '${p.alt} ${p.name} ${p.id} ${p.sectorName}'.trim();
      return matches(hay);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Other Products',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          productsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                e.toString().replaceFirst('Exception: ', ''),
                style: TextStyle(color: cs.error),
              ),
            ),
            data: (list) {
              final filtered = _filterProducts(list);
              if (filtered.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('No products.'));
              }

              // Safety cap to avoid rendering extremely large lists.
              final display =
                  (filtered.length > 80) ? filtered.sublist(0, 80) : filtered;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: display
                      .map(
                        (p) => _AltCard(
                          key: ValueKey(p.id.isNotEmpty ? p.id : p.alt),
                          alt: p.alt,
                          onTap: () {
                            // Open the same Online Brands page, but using the
                            // /api/online/product-details/brands/ endpoint.
                            //
                            // We pass the backend "key" as `q` (string id from
                            // products-without-groups API). `search=startswith`
                            // matches the backend behavior you confirmed via curl.
                            final key = (p.id.trim().isNotEmpty)
                                ? p.id.trim()
                                : p.alt.trim();

                            context.go(
                              '${R.onlineBrands}/0'
                              '?q=${Uri.encodeComponent(key)}'
                              '&search=startswith',
                            );
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AltCard extends StatelessWidget {
  final String alt;
  final VoidCallback? onTap;

  const _AltCard({
    super.key,
    required this.alt,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: alt,
      waitDuration: const Duration(milliseconds: 250),
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: .35)),
          ),
          child: Text(
            alt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String title;
  final String imageUrl;
  final VoidCallback? onTap;

  const _GroupCard({
    required this.title,
    required this.imageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Tooltip gives the hover hint on web/desktop (and long-press on mobile).
    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 250),
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: AppCacheManager.images,
                fit: BoxFit.contain,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (context, _) => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, _, __) => const Center(
                  child: Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Title: single-line, trimmed with "..."
            SizedBox(
              width: 84,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 160,
                height: 16,
                color: cs.surfaceContainerHighest.withValues(alpha: .5),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(6, (_) {
                    return Container(
                      width: 68,
                      height: 68,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// Home intentionally opts out of scrollbars via [EvolutionScrollBehavior].
