import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/route_names.dart';
import '../../data/models/online_brand_payload.dart';
import '../../data/models/online_customer_info.dart';
import '../../services/api_service.dart';
import '../../state/currency_provider.dart';
import '../../state/page_refresh_provider.dart';
import '../../state/current_balance_provider.dart';
import '../../state/online_brands_provider.dart';
import '../../state/online_brand_selection_provider.dart';
import '../../state/online_customer_info_provider.dart';
import '../../state/online_purchase_criteria_provider.dart';
import '../../state/online_flow_state_provider.dart';
import '../../state/session_provider.dart';
import '../../utils/contact_phone_picker.dart';
import '../../widgets/grid_scroll_container.dart';
import '../../widgets/error_message.dart';
import '../../widgets/page_nav.dart';
import '../../widgets/history_text_field.dart';
import 'widgets/online_brand_card.dart';
import 'widgets/cv_pricing_brand_card.dart';

class OnlineBrandSelectionPage extends ConsumerStatefulWidget {
  final int groupDetailId;
  final int? initialGsd;
  final String? productKey;
  final String? searchMode;

  const OnlineBrandSelectionPage({
    super.key,
    required this.groupDetailId,
    this.initialGsd,
    this.productKey,
    this.searchMode,
  });

  @override
  ConsumerState<OnlineBrandSelectionPage> createState() =>
      _OnlineBrandSelectionPageState();
}

class _OnlineBrandSelectionPageState
    extends ConsumerState<OnlineBrandSelectionPage> {
  final _searchCtl = TextEditingController();
  final _accountCtl = TextEditingController();
  final _pageScrollController = ScrollController();
  final _tabsScrollController = ScrollController();

  double? _pendingPageScrollOffset;
  double? _pendingTabsScrollOffset;

  // CV pricing flow: page-level Next triggers card submit; Next enabled only when valid.
  final ValueNotifier<int> _cvSubmitPulse = ValueNotifier<int>(0);
  final ValueNotifier<bool> _cvValidNotifier = ValueNotifier<bool>(false);

  // Bonus: show Next also for non-CV tabs (disabled until a brand is selected).
  static const bool _showNextForNonCv = true;

  OnlineCvPricingFlowState? _queuedCvPricingState;
  bool _cvPricingPersistQueued = false;

  String _q = '';
  int? _gsd; // selected tab id

  // Customer-info flow (for tabs with has_info=true)
  bool _infoLoading = false;
  bool _lookupBusy = false;
  OnlineCustomerInfoResponse? _customerInfo;
  String? _customerInfoError;

  // Track whether the user has attempted a customer lookup at least once.
  bool _didFetchCustomerInfo = false;

  // Currency used for the last customer-info request (so we can auto-refresh when it changes).
  String? _customerInfoCurrency;

  // Backend tabs commonly use a stable "Direct Refill" id. If the caller did
  // not provide ?gsd, default to this to avoid an extra "no-gsd" request.
  static const int _defaultGsd = 1;

  String get _flowRouteKey => [
        widget.groupDetailId.toString(),
        (widget.initialGsd ?? _defaultGsd).toString(),
        widget.productKey ?? '',
        widget.searchMode ?? '',
      ].join('|');

  void _persistBrandFlow() {
    if (!mounted) return;
    final currentBrand = ref.read(onlineFlowProvider).brand;
    final preservedCv =
        (currentBrand != null && currentBrand.routeKey == _flowRouteKey)
            ? currentBrand.cvPricingState
            : null;

    ref.read(onlineFlowProvider.notifier).saveBrand(
          OnlineBrandFlowState(
            routeKey: _flowRouteKey,
            selectedGsd: _gsd ?? _defaultGsd,
            searchText: _searchCtl.text,
            accountText: _accountCtl.text,
            pageScrollOffset: _pageScrollController.hasClients
                ? _pageScrollController.offset
                : (_pendingPageScrollOffset ?? 0),
            tabsScrollOffset: _tabsScrollController.hasClients
                ? _tabsScrollController.offset
                : (_pendingTabsScrollOffset ?? 0),
            didFetchCustomerInfo: _didFetchCustomerInfo,
            customerInfoCurrency: _customerInfoCurrency,
            customerInfoResponse: _customerInfo == null
                ? null
                : OnlineCustomerInfoResponse(
                    success: _customerInfo!.success,
                    message: _customerInfo!.message,
                    error: _customerInfo!.error,
                    data: _customerInfo!.data == null
                        ? null
                        : Map<String, dynamic>.from(_customerInfo!.data!),
                    availableBrands: _customerInfo!.availableBrands == null
                        ? null
                        : List<int>.from(_customerInfo!.availableBrands!),
                  ),
            customerInfoError: _customerInfoError,
            cvPricingState: preservedCv,
          ),
        );
  }

  void _scheduleCvPricingStatePersist(OnlineCvPricingFlowState? value) {
    _queuedCvPricingState = value;
    if (_cvPricingPersistQueued) return;
    _cvPricingPersistQueued = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cvPricingPersistQueued = false;
      if (!mounted) return;

      final queued = _queuedCvPricingState;
      _queuedCvPricingState = null;

      ref.read(onlineFlowProvider.notifier).updateBrandCvPricing(
        routeKey: _flowRouteKey,
        value: queued,
      );
    });
  }

  void _restoreCustomerInfoFromFlow() {
    final flow = ref.read(onlineFlowProvider).brand;
    if (flow == null || flow.routeKey != _flowRouteKey) return;
    if (flow.selectedGsd != (_gsd ?? _defaultGsd)) return;

    _didFetchCustomerInfo = flow.didFetchCustomerInfo;
    _customerInfoCurrency = flow.customerInfoCurrency;
    _customerInfoError = flow.customerInfoError;
    _customerInfo = flow.customerInfoResponse == null
        ? null
        : OnlineCustomerInfoResponse(
            success: flow.customerInfoResponse!.success,
            message: flow.customerInfoResponse!.message,
            error: flow.customerInfoResponse!.error,
            data: flow.customerInfoResponse!.data == null
                ? null
                : Map<String, dynamic>.from(flow.customerInfoResponse!.data!),
            availableBrands: flow.customerInfoResponse!.availableBrands == null
                ? null
                : List<int>.from(flow.customerInfoResponse!.availableBrands!),
          );

    if (_customerInfo?.success == true && _accountCtl.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(onlineCustomerInfoProvider.notifier).state = OnlineCustomerInfoState(
          accountNumber: _accountCtl.text.trim(),
          groupSubdetailId: _gsd ?? _defaultGsd,
          response: _customerInfo!,
        );
      });
    }
  }

  void _restoreScrollPositions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tabsOffset = _pendingTabsScrollOffset;
      if (tabsOffset != null && _tabsScrollController.hasClients) {
        final max = _tabsScrollController.position.maxScrollExtent;
        _tabsScrollController.jumpTo(tabsOffset.clamp(0, max));
        _pendingTabsScrollOffset = null;
      }

      final pageOffset = _pendingPageScrollOffset;
      if (pageOffset != null && _pageScrollController.hasClients) {
        final max = _pageScrollController.position.maxScrollExtent;
        _pageScrollController.jumpTo(pageOffset.clamp(0, max));
        _pendingPageScrollOffset = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();

    final saved = ref.read(onlineFlowProvider).brand;
    if (saved != null && saved.routeKey == _flowRouteKey) {
      _gsd = saved.selectedGsd;
      _q = saved.searchText;
      if (saved.searchText.isNotEmpty) {
        _searchCtl.text = saved.searchText;
      }
      if (saved.accountText.isNotEmpty) {
        _accountCtl.text = saved.accountText;
      }
      _pendingPageScrollOffset = saved.pageScrollOffset;
      _pendingTabsScrollOffset = saved.tabsScrollOffset;
      _restoreCustomerInfoFromFlow();
    } else {
      _gsd = widget.initialGsd ?? _defaultGsd;
    }

    _searchCtl.addListener(() {
      final v = _searchCtl.text;
      if (v != _q) {
        setState(() => _q = v);
      }
      _persistBrandFlow();
    });
    _accountCtl.addListener(_persistBrandFlow);
    _pageScrollController.addListener(_persistBrandFlow);
    _tabsScrollController.addListener(_persistBrandFlow);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreScrollPositions();
      _persistBrandFlow();
    });
  }

  @override
  void dispose() {
    _persistBrandFlow();
    _pageScrollController.dispose();
    _tabsScrollController.dispose();
    _searchCtl.dispose();
    _accountCtl.dispose();
    _cvSubmitPulse.dispose();
    _cvValidNotifier.dispose();
    super.dispose();
  }

  static String _pickClientName(Map<String, dynamic> row) {
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == 'clientname') {
        return (entry.value ?? '').toString().trim();
      }
    }
    return '';
  }

  static String _pickByKey(Map<String, dynamic> row, String key) {
    final lower = key.toLowerCase();
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == lower) {
        return (entry.value ?? '').toString().trim();
      }
    }
    return '';
  }

  void _snack(String msg, {bool error = false}) {
    final m = msg.trim();
    if (m.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      content: Text(m),
    ));
  }

  Future<void> _showGroupTabLookupDialog({
    required int groupSubdetailId,
    required String dataKey,
  }) async {
    if (_lookupBusy) return;
    setState(() => _lookupBusy = true);

    List<Map<String, dynamic>>? results;
    String? fetchError;

    try {
      final username = ref.read(sessionProvider).username;
      results = await ApiService.instance.getProductDictionaryLookup(
        user: username,
        groupTab: groupSubdetailId,
        dataKey: dataKey,
      );
    } catch (e) {
      fetchError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }

    if (!mounted) return;
    if (fetchError != null) { _snack(fetchError, error: true); return; }
    if (results == null || results.isEmpty) { _snack('No results found.'); return; }

    final showValueCol = dataKey.toLowerCase() != 'clientname' &&
        results.any((r) => _pickByKey(r, dataKey).isNotEmpty);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select client',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showValueCol)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Name',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600)),
                        ),
                        Text(dataKey,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: results!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final row = results![i];
                    final clientname = _pickClientName(row);
                    final value =
                        showValueCol ? _pickByKey(row, dataKey) : '';
                    return ListTile(
                      dense: true,
                      title: Text(
                        clientname.isNotEmpty ? clientname : value,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      trailing: (showValueCol && value.isNotEmpty)
                          ? Text(value,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700))
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        final fill =
                            value.isNotEmpty ? value : clientname;
                        if (fill.isNotEmpty) _accountCtl.text = fill;
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  TextInputType _infoKeyboardType(String helperText) {
    return ContactPhonePicker.looksLikePhoneHint(helperText)
        ? TextInputType.phone
        : TextInputType.text;
  }

  String _selectedCurrencyCode(WidgetRef ref) {
    // Prefer the server/session currency (from currentBalanceProvider), so
    // brand API calls always match what the user selected in the currency chips.
    ref.watch(currentBalanceProvider); // subscribe to updates
    final active = ref.read(currentBalanceProvider.notifier).activeCurrency;
    if (active != null && active.trim().isNotEmpty) {
      return active.toUpperCase();
    }

    // Fallback: legacy local currency state (used by some filters/pages)
    final cs = ref.watch(currencyProvider);
    return cs.selected.code.toUpperCase();
  }

  void _refresh(OnlineBrandsQuery q) {
    ref.invalidate(onlineBrandsPayloadProvider(q));
  }

  void _resetCustomerInfo() {
    _customerInfo = null;
    _customerInfoError = null;
    _infoLoading = false;
    _didFetchCustomerInfo = false;
    _customerInfoCurrency = null;
    // Also clear persisted customer-info (used later in order step).
    ref.read(onlineCustomerInfoProvider.notifier).state = null;
    _persistBrandFlow();
  }

  String _helperTextFromParams(OnlineSubdetailTab? tab) {
    final p = tab?.params ?? const [];
    // Convention: [method, provider, service, helperText, ...]
    if (p.length >= 4) {
      final s = (p[3] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    // Fallback by method
    final method =
        p.isNotEmpty ? (p[0] ?? '').toString().toLowerCase().trim() : '';
    if (method == 'power_ogero') return 'Enter Ogero account number';
    if (method == 'moonet') return 'Enter account number';
    return 'Enter account number';
  }

  Future<void> _fetchCustomerInfo({required int groupSubdetailId}) async {
    final acc = _accountCtl.text.trim();
    if (acc.isEmpty) {
      setState(() => _customerInfoError = 'Please enter an account number.');
      _persistBrandFlow();
      return;
    }
    if (_infoLoading) return;

    _didFetchCustomerInfo = true;
    setState(() {
      _infoLoading = true;
      _customerInfo = null;
      _customerInfoError = null;
    });

    try {
      final currency = _selectedCurrencyCode(ref);
      _customerInfoCurrency = currency;
      final resp = await ApiService.instance.getOnlineCustomerInfo(
        accountNumber: acc,
        groupSubdetailId: groupSubdetailId,
        currency: currency,
      );
      if (!mounted) return;

      // Keep the successful lookup available for later steps (order page).
      if (resp.success == true) {
        ref.read(onlineCustomerInfoProvider.notifier).state =
            OnlineCustomerInfoState(
          accountNumber: acc,
          groupSubdetailId: groupSubdetailId,
          response: resp,
        );
      } else {
        ref.read(onlineCustomerInfoProvider.notifier).state = null;
      }

      final msg = (resp.error ?? '').trim().isNotEmpty
          ? (resp.error ?? '').trim()
          : resp.message.trim();

      setState(() {
        _infoLoading = false;
        _customerInfo = resp;
        _customerInfoError =
            resp.success ? null : (msg.isNotEmpty ? msg : 'Request failed.');
      });
      _persistBrandFlow();
    } catch (e) {
      if (!mounted) return;

      // Clear any previously cached customer-info on network/parse failures.
      ref.read(onlineCustomerInfoProvider.notifier).state = null;

      setState(() {
        _infoLoading = false;
        _customerInfo = null;
        _customerInfoError =
            e.toString().replaceFirst('Exception: ', '').trim();
      });
      _persistBrandFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = _selectedCurrencyCode(ref);

    // IMPORTANT: do NOT overwrite `_customerInfoCurrency` here.
    // `_customerInfoCurrency` must reflect the currency used for the *last*
    // customer-info request, so we can detect currency changes and re-fetch
    // customer-info when needed.

    final query = OnlineBrandsQuery(
      groupDetailId: widget.groupDetailId,
      productKey: widget.productKey,
      searchMode: widget.searchMode,
      currency: currency,
      gsd: _gsd,
    );

    // Same refresh behavior as other pages: listen to global pulse.
    ref.listen<int>(pageRefreshPulseProvider, (prev, next) {
      if (prev == next) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent != true) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refresh(query);
      });
    });

    final async = ref.watch(onlineBrandsPayloadProvider(query));
    final selection = ref.watch(onlineBrandSelectionProvider);

    // Next is only relevant for the CableVision (CV) pricing flow.
    final showCvNext = async.maybeWhen(
      data: (p) => p.active.cvPricing.isNotEmpty,
      orElse: () => false,
    );

    final activeSubdetailId = async.maybeWhen(
      data: (p) => p.active.subdetailId,
      orElse: () => null,
    );

    final canNonCvNext = _showNextForNonCv &&
        selection != null &&
        activeSubdetailId != null &&
        selection.subdetailId == activeSubdetailId &&
        selection.brandId > 0;

    final showNext = showCvNext || _showNextForNonCv;

    return ValueListenableBuilder<bool>(
      valueListenable: _cvValidNotifier,
      builder: (context, cvValid, _) {
        final nextEnabled = showCvNext ? cvValid : canNonCvNext;

        return PageNav(
          config: PageNavConfig(
            backTo: R.home,
            showNext: showNext,
            nextEnabled: nextEnabled,
            onNext: showNext
                ? () async {
                    if (showCvNext) {
                      // Trigger CV submit (validation + draft build) via the card.
                      _cvSubmitPulse.value = _cvSubmitPulse.value + 1;
                      return;
                    }

                    // Bonus non-CV next: go to purchase only if a brand is selected for this tab.
                    if (canNonCvNext) {
                      context.go(R.purchase);
                    }
                  }
                : null,
          ),
          child: GridScrollContainer(
        controller: _pageScrollController,
        child: LayoutBuilder(
        builder: (context, c) {
          final isMobile = c.maxWidth < 720;

          final body = async.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 60),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ErrorMessage(
                    message: e.toString().replaceFirst('Exception: ', ''),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _refresh(query),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (payload) {
          final tabs = payload.tabs;
          final activeId = (payload.activeSubdetailId != 0)
              ? payload.activeSubdetailId
              : (_gsd ?? _defaultGsd);

          OnlineSubdetailTab? activeTab;
          if (tabs.isNotEmpty) {
            activeTab = tabs.firstWhere(
              (t) => t.id == activeId,
              orElse: () => tabs.first,
            );
          }

          final title = (activeTab == null)
              ? payload.groupDetail.name
              : '${payload.groupDetail.name} - ${activeTab.name}';

          final hasInfo = activeTab?.hasInfo == true;
          final helperText = _helperTextFromParams(activeTab);

          // If the user already attempted a customer lookup, and they change currency while staying
          // on a has-info tab, refresh the customer-info using the new currency.
          if (hasInfo &&
              _didFetchCustomerInfo &&
              !_infoLoading &&
              (_accountCtl.text.trim().isNotEmpty) &&
              (_customerInfoCurrency ?? '') != currency) {
            // Prevent repeated scheduling within the same rebuild.
            _customerInfoCurrency = currency;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (activeTab?.hasInfo != true) return;
              if (_accountCtl.text.trim().isEmpty) return;
              if (_infoLoading) return;
              _fetchCustomerInfo(groupSubdetailId: activeId);
            });
          }

          final rawQ = _q.trim().toLowerCase();

          // UX: hide the search filter when the list is small (no need to search < 4 cards).
          int searchPoolCount = 0;
          bool canSearch = false;

          List<OnlineBrand> brands;

          if (hasInfo) {
            // Do not show brands until the user performs the customer lookup.
            if (_customerInfo?.success == true) {
              final allowed = _customerInfo!.availableBrands;
              List<OnlineBrand> base;

              if (allowed == null) {
                base = payload.active.brands;
              } else {
                final allowSet = allowed.toSet();
                base = payload.active.brands
                    .where((b) => allowSet.contains(b.id))
                    .toList(growable: false);
              }

              searchPoolCount = base.length;
              canSearch = searchPoolCount >= 4;

              // Only apply search when we show the search UI.
              final q = canSearch ? rawQ : '';
              if (q.isNotEmpty) {
                base = base.where((b) {
                  final hay = [
                    b.displayName,
                    b.name,
                    b.alt,
                    b.productName,
                    b.unit,
                  ].join(' ').toLowerCase();
                  return hay.contains(q);
                }).toList(growable: false);
              }

              brands = base;
            } else {
              brands = const <OnlineBrand>[];
            }
          } else {
            final base = payload.active.brands;
            searchPoolCount = base.length;
            canSearch = searchPoolCount >= 4;

            final q = canSearch ? rawQ : '';
            brands = base.where((b) {
              if (q.isEmpty) return true;
              final hay = [
                b.displayName,
                b.name,
                b.alt,
                b.productName,
                b.unit,
              ].join(' ').toLowerCase();
              return hay.contains(q);
            }).toList(growable: false);
          }

          // SPECIAL CASE: if API returns CV pricing, we show the CV form card UI
          // and we do NOT show the normal "Search brands…" filter.
          final hasCvPricing = payload.active.cvPricing.isNotEmpty;
          if (hasCvPricing) {
            canSearch = false;
          }

          // If search is disabled (small list OR CV pricing), ensure any previous query is cleared.
          if (!canSearch && _searchCtl.text.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_searchCtl.text.isNotEmpty) _searchCtl.clear();
            });
          }

          // Show the CV card when cvPricing exists and there is at least one brand in active.brands.
          // If the tab is has_info, we wait until customer-info succeeds (because brands list is gated).
          final showCvPricingCard = hasCvPricing &&
              brands.isNotEmpty &&
              (!hasInfo || (_customerInfo?.success == true));

          // UX: if there is only ONE available brand in the active tab (and this is not the CV flow),
          // auto-select it so the page-level Next behaves as if the user tapped the brand.
          // NOTE: We base this on the *full* available pool (before any search filtering).
          final shouldAutoSelectSingleBrand =
              !hasCvPricing && searchPoolCount == 1 && brands.length == 1;
          if (shouldAutoSelectSingleBrand) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              final b = brands.first;

              // Keep criteria_info clean for non-CV flows when Next is used without tapping.
              if (!hasInfo) {
                ref.read(onlinePurchaseCriteriaProvider.notifier).state = null;
              } else {
                // For has_info tabs, persist the fetched customer-info as criteria_info
                // (same shape as the brand-card onTap), so Purchase page/back-end receives it.
                final infoState = ref.read(onlineCustomerInfoProvider);
                final merged = <String, dynamic>{'has_info': true};
                final d = infoState?.response.data;
                if (d != null && d.isNotEmpty) {
                  merged.addAll(d);
                }
                if (infoState != null &&
                    !merged.containsKey('account_number') &&
                    infoState.accountNumber.trim().isNotEmpty) {
                  merged['account_number'] = infoState.accountNumber.trim();
                }
                ref.read(onlinePurchaseCriteriaProvider.notifier).state = merged;
              }

              final sel = ref.read(onlineBrandSelectionProvider);
              if (sel != null &&
                  sel.subdetailId == payload.active.subdetailId &&
                  sel.brandId == b.id) {
                return;
              }

              ref.read(onlineBrandSelectionProvider.notifier).state =
                  OnlineBrandSelection(
                brandId: b.id,
                subdetailId: payload.active.subdetailId,
              );
            });
          }

              _restoreScrollPositions();

              return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabsRow(
                controller: _tabsScrollController,
                tabs: tabs,
                activeId: activeId,
                onTap: (id) {
                  if (id == _gsd) return;
                  setState(() {
                    _gsd = id;
                    _searchCtl.clear();
                    _q = '';
                    _accountCtl.clear();
                    _resetCustomerInfo();
                    FocusScope.of(context).unfocus();
                  });
                  _cvValidNotifier.value = false;
                  _persistBrandFlow();
                },
              ),
              const SizedBox(height: 14),
              Text(
                title.toUpperCase(),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),

              // has_info UI
              if (hasInfo)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: HistoryTextField(
                            historyKey: 'online.account_lookup',
                            controller: _accountCtl,
                            keyboardType: _infoKeyboardType(helperText),
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: helperText,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              prefixIcon: const Icon(Icons.person),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Lookup',
                          icon: _lookupBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5),
                                )
                              : Icon(Icons.search,
                                  color: Colors.grey.shade600),
                          onPressed: _lookupBusy
                              ? null
                              : () => _showGroupTabLookupDialog(
                                    groupSubdetailId: activeId,
                                    dataKey: helperText,
                                  ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: _infoLoading
                              ? null
                              : () => _fetchCustomerInfo(
                                    groupSubdetailId:
                                        payload.active.subdetailId,
                                  ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                          child: _infoLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Info'),
                        ),
                      ],
                    ),
                    if (_customerInfoError != null &&
                        _customerInfoError!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ErrorMessage(message: _customerInfoError!),
                      ),
                    if (_customerInfo == null && !_infoLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Enter the account number and press Info to load the available brands.',
                        ),
                      ),
                    if (_customerInfo?.success == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _CustomerInfoCard(info: _customerInfo!.data),
                      ),

                    // Only show search UI when:
                    // - customer info succeeded
                    // - and there is no CV pricing
                    // - and list is large enough
                    if (_customerInfo?.success == true && canSearch) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: HistoryTextField(
                              historyKey: 'online.brand_search',
                              controller: _searchCtl,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'Search brands…',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) {
                                if (_q == value) return;
                                setState(() => _q = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _searchCtl.text.isEmpty
                                ? null
                                : () {
                                    _searchCtl.clear();
                                    FocusScope.of(context).unfocus();
                                  },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              textStyle: const TextStyle(fontSize: 13),
                            ),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ],
                  ],
                )
              else if (canSearch)
                Row(
                  children: [
                    Expanded(
                      child: HistoryTextField(
                        historyKey: 'online.brand_search',
                        controller: _searchCtl,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search brands…',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          if (_q == value) return;
                          setState(() => _q = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _searchCtl.text.isEmpty
                          ? null
                          : () {
                              _searchCtl.clear();
                              FocusScope.of(context).unfocus();
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),

              const SizedBox(height: 14),

              // SPECIAL CV CARD (replaces the normal grid when cvPricing exists)
              if (showCvPricingCard) ...[
                CvPricingBrandCard(
                  key: ValueKey<String>('cv_${payload.active.subdetailId}_$currency'),
                  subdetailId: payload.active.subdetailId,
                  initialState: (() {
                    final flow = ref.read(onlineFlowProvider).brand;
                    if (flow == null || flow.routeKey != _flowRouteKey) return null;
                    final cv = flow.cvPricingState;
                    if (cv == null || cv.subdetailId != payload.active.subdetailId) {
                      return null;
                    }
                    return cv;
                  })(),
                  onStateChanged: (value) {
                    _scheduleCvPricingStatePersist(value);
                  },
                  cvPricing: payload.active.cvPricing,
                  maxSlaves: payload.active.maxSlaves,
                  slaveCustomerPriceDay: payload.active.slaveCustomerPriceDay,
                  activeBrand: payload.active.brands.isNotEmpty
                      ? payload.active.brands.first
                      : null,
                  onHistorySearch: (q) {
                    // Optional: wire to a backend endpoint if/when available.
                  },
                  // Replace the in-card Order button with the page-level Next.
                  showOrderButton: false,
                  submitSignal: _cvSubmitPulse,
                  onValidChanged: (v) {
                    if (_cvValidNotifier.value == v) return;
                    _cvValidNotifier.value = v;
                  },
                  onOrder: (draft) {
                    if (!mounted) return;

                    // Store criteria_info for the next step (purchase page).
                    final ci = draft['criteria_info'];
                    ref.read(onlinePurchaseCriteriaProvider.notifier).state =
                        (ci is Map) ? ci.cast<String, dynamic>() : null;

                    // Select the (single) CV brand in this tab.
                    if (payload.active.brands.isNotEmpty) {
                      final b = payload.active.brands.first;
                      ref.read(onlineBrandSelectionProvider.notifier).state =
                          OnlineBrandSelection(
                        brandId: b.id,
                        subdetailId: payload.active.subdetailId,
                      );
                    }

                    // Go to purchase.
                    context.go(R.purchase);
                  },
                ),
              ] else if (!hasInfo) ...[
                if (brands.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(child: Text('No brands found.')),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: brands.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 460,
                      mainAxisExtent: 180,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemBuilder: (context, i) {
                      final b = brands[i];
                      final isSelected = selection != null &&
                          selection.brandId == b.id &&
                          selection.subdetailId == payload.active.subdetailId;

                      return OnlineBrandCard(
                        brand: b,
                        mainLogoUrl: payload.groupDetail.avatar,
                        subdetailLabel: activeTab?.name ?? '',
                        selected: isSelected,
                        onTap: () {
                          // Clear any previous criteria_info (only CV flow sets it).
                          ref.read(onlinePurchaseCriteriaProvider.notifier).state = null;

                          ref.read(onlineBrandSelectionProvider.notifier).state =
                              OnlineBrandSelection(
                            brandId: b.id,
                            subdetailId: payload.active.subdetailId,
                          );

                          // Non-CV flow: open Purchase immediately.
                          context.go(R.purchase);
                        },
                      );
                    },
                  ),
              ] else ...[
                // hasInfo grid (unchanged)
                if (_customerInfo?.success == true) ...[
                  if (brands.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: Center(
                        child: Text('No available brands for this account.'),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: brands.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 460,
                        mainAxisExtent: 180,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemBuilder: (context, i) {
                        final b = brands[i];
                        final isSelected = selection != null &&
                            selection.brandId == b.id &&
                            selection.subdetailId == payload.active.subdetailId;

                        final totalRaw =
                            ((_customerInfo?.data?['total_amount_cur'] ??
                                    _customerInfo?.data?['total'] ??
                                    ''))
                                .toString()
                                .trim();

                        return OnlineBrandCard(
                          brand: b,
                          mainLogoUrl: payload.groupDetail.avatar,
                          subdetailLabel: activeTab?.name ?? '',
                          overridePriceRaw:
                              totalRaw.isNotEmpty ? totalRaw : null,
                          overridePriceCurrency: currency,
                          selected: isSelected,
                          onTap: () {
                            // Persist has_info so the purchase flow and backend can treat it
                            // similarly to CV (criteria_info present).
                            final infoState = ref.read(onlineCustomerInfoProvider);
                            final merged = <String, dynamic>{'has_info': true};
                            final d = infoState?.response.data;
                            if (d != null && d.isNotEmpty) {
                              merged.addAll(d);
                            }
                            if (infoState != null &&
                                !merged.containsKey('account_number') &&
                                infoState.accountNumber.trim().isNotEmpty) {
                              merged['account_number'] = infoState.accountNumber.trim();
                            }
                            ref.read(onlinePurchaseCriteriaProvider.notifier).state = merged;

                            ref.read(onlineBrandSelectionProvider.notifier).state =
                                OnlineBrandSelection(
                              brandId: b.id,
                              subdetailId: payload.active.subdetailId,
                            );

                            // has_info flow: open Purchase immediately.
                            context.go(R.purchase);
                          },
                        );
                      },
                    ),
                ],
              ],

              const SizedBox(height: 6),
            ],
              );
            },
          );

          if (isMobile) return body;

          // Desktop/tablet: avoid full-width stretching.
          // Keep the layout consistent with card sizing (maxCrossAxisExtent ~460).
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: body,
            ),
          );
        },
      ),
      ),
        );
      },
    );
  }
}

class _TabsRow extends StatelessWidget {
  final ScrollController controller;
  final List<OnlineSubdetailTab> tabs;
  final int activeId;
  final ValueChanged<int> onTap;

  const _TabsRow({
    required this.controller,
    required this.tabs,
    required this.activeId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ChoiceChip(
                  label: Text(t.name.toUpperCase()),
                  selected: t.id == activeId,
                  selectedColor: const Color(0xFFB3261E),
                  labelStyle: TextStyle(
                    fontSize: 11, // NEW: smaller tab text
                    fontWeight: FontWeight.w800,
                    color: (t.id == activeId)
                        ? Colors.white
                        : const Color(0xFFB3261E),
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFB3261E)),
                  onSelected: (_) => onTap(t.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomerInfoCard extends StatelessWidget {
  final Map<String, dynamic>? info;

  const _CustomerInfoCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final m = info ?? const <String, dynamic>{};

    String v(String key) {
      final raw = m[key];
      if (raw == null) return '';
      return raw.toString().trim();
    }

    bool isRtlText(String s) {
      // Arabic + extended Arabic blocks.
      return RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿ]').hasMatch(s);
    }

    final rows = <MapEntry<String, String>>[];

    void addRow(String label, String value) {
      final s = value.trim();
      if (s.isEmpty || s == 'null' || s == '-') return;
      rows.add(MapEntry(label, s));
    }

    final acc = v('account_number');
    final accId = v('account_id');
    if (acc.isNotEmpty && accId.isNotEmpty && acc == accId) {
      addRow('Account ID', accId);
    } else {
      addRow('Account', acc);
      addRow('Account ID', accId);
    }

    addRow('Name', v('full_name'));
    addRow('Plan', v('current_plan'));
    addRow('Expiry', v('expiry_date'));
    addRow('Idle days', v('idle_days'));
    addRow('Invoices', v('total_invoices'));
    addRow('Amount', v('amount_cur'));
    addRow('Fees', v('fees_cur'));
    addRow('Total', v('total_amount_cur'));

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.red.shade700,
        );
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.green.shade700,
        );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Customer info'.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Text('No customer details returned by the provider.')
            else
              ...rows.map(
                (e) {
                  final rtl = isRtlText(e.value);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            e.key,
                            style: labelStyle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.value,
                            style: valueStyle,
                            textDirection:
                                rtl ? TextDirection.rtl : TextDirection.ltr,
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}