import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/online_purchase_order.dart';
import '../../routing/route_names.dart';
import '../../services/api_service.dart';
import '../../state/current_balance_provider.dart';
import '../../state/currency_provider.dart';
import '../../state/online_brand_selection_provider.dart';
import '../../state/online_customer_info_provider.dart';
import '../../state/online_purchase_criteria_provider.dart';
import '../../state/nav_history_provider.dart';
import '../../state/page_refresh_provider.dart';
import '../../state/session_provider.dart';
import '../../state/online_flow_state_provider.dart';
import '../../utils/contact_phone_picker.dart';
import '../../utils/money_format.dart';
import '../../utils/note_actions.dart';
import '../../utils/note_pretty.dart';
import '../../widgets/error_message.dart';
import '../../widgets/grid_scroll_container.dart';
import '../../widgets/page_nav.dart';
import '../../widgets/history_text_field.dart';

class PurchasePage extends ConsumerStatefulWidget {
  const PurchasePage({super.key});

  @override
  ConsumerState<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends ConsumerState<PurchasePage> {
  final _pinCtl = TextEditingController();
  final _fullNameCtl = TextEditingController();
  final _dealerTotalCtl = TextEditingController();
  final _customerTotalCtl = TextEditingController();
  final _quantityCtl = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();
  final _pageScrollController = ScrollController();

  Map<String, String>? _pendingParamValues;
  double? _pendingPageScrollOffset;

  // Used for instant re-pricing on quantity changes.
  // _unitNativeCost is derived from server total_native_cost / quantity.
  num? _unitNativeCost;
  double _profitPct = 0; // profit_percentage
  double _sellingProfitPct = 0; // selling_profit_percentage

  final Map<String, TextEditingController> _paramCtrls = {};

  OnlinePurchaseOrderData? _order;
  bool _loading = false;
  bool _posting = false;
  bool _lookupBusy = false;
  String? _error;
  bool _showPriceDetails = true;

  // Quantity may be initially unknown. We send 0 to the preview endpoint,
  // allowing the backend to treat it as "use minimum/default".
  // This avoids an initial preview call with quantity=1 followed by a
  // corrective second call.
  int _quantity = 0;
  String? _activeCurrency; // code (LBP/USD)

  String _orderUuid = _uuidV4();
  int _reqSeq = 0;

  // Smaller, denser UI
  static const double _fsBase = 13;
  static const double _fsLabel = 12;
  static const double _fsHeader = 14;

  static const String _cableVisionSlaveRefillBrandName =
      'CABLE VISION SLAVE REFILL';
  static const String _slaveQuantityParamName =
      'SLAVE QUANTITY [1,2,3]';

  String get _selectionFlowKey {
    final sel = ref.read(onlineBrandSelectionProvider);
    if (sel == null) return '';
    return '${sel.subdetailId}|${sel.brandId}';
  }

  void _persistPurchaseFlow() {
    if (!mounted) return;
    final key = _selectionFlowKey;
    if (key.isEmpty) return;

    ref.read(onlineFlowProvider.notifier).savePurchase(
          OnlinePurchaseFlowState(
            selectionKey: key,
            pin: _pinCtl.text,
            fullName: _fullNameCtl.text,
            quantity: _quantity > 0 ? _quantity : 0,
            showPriceDetails: _showPriceDetails,
            params: {
              for (final entry in _paramCtrls.entries) entry.key: entry.value.text,
            },
            criteriaInfo: () {
              final criteria = _criteriaInfoFromProviders();
              return criteria == null ? null : Map<String, dynamic>.from(criteria);
            }(),
            pageScrollOffset: _pageScrollController.hasClients
                ? _pageScrollController.offset
                : (_pendingPageScrollOffset ?? 0),
          ),
        );
  }

  void _restorePurchaseFlowIfAny() {
    final saved = ref.read(onlineFlowProvider).purchase;
    final key = _selectionFlowKey;
    if (saved == null || key.isEmpty || saved.selectionKey != key) return;

    if (saved.pin.isNotEmpty) _pinCtl.text = saved.pin;
    if (saved.fullName.isNotEmpty) _fullNameCtl.text = saved.fullName;
    if (saved.quantity > 0) {
      _quantity = saved.quantity;
      _quantityCtl.text = saved.quantity.toString();
    }
    _showPriceDetails = saved.showPriceDetails;
    _pendingParamValues = Map<String, String>.from(saved.params);
    _pendingPageScrollOffset = saved.pageScrollOffset;
    if (saved.criteriaInfo != null && saved.criteriaInfo!.isNotEmpty) {
      final restoredCriteria = Map<String, dynamic>.from(saved.criteriaInfo!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(onlinePurchaseCriteriaProvider.notifier).state = restoredCriteria;
      });
    }
  }

  void _restoreScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingPageScrollOffset;
      if (pending == null || !_pageScrollController.hasClients) return;
      final max = _pageScrollController.position.maxScrollExtent;
      _pageScrollController.jumpTo(pending.clamp(0, max));
      _pendingPageScrollOffset = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _showPriceDetails = ref.read(sessionProvider).showDealerPrice;
    _restorePurchaseFlowIfAny();

    _pinCtl.addListener(_persistPurchaseFlow);
    _fullNameCtl.addListener(_persistPurchaseFlow);
    _quantityCtl.addListener(_persistPurchaseFlow);
    _pageScrollController.addListener(_persistPurchaseFlow);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Prefer the server/session active currency (same one shown in the top chips)
      // so the purchase page does not default to LBP when USD is currently active.
      final serverActive = ref
          .read(currentBalanceProvider.notifier)
          .activeCurrency
          ?.trim()
          .toUpperCase();

      if (serverActive != null && serverActive.isNotEmpty) {
        // Keep legacy currencyProvider in sync (used by this page listeners).
        final cs = ref.read(currencyProvider);
        final idx = cs.all.indexWhere(
          (c) => c.code.trim().toUpperCase() == serverActive,
        );
        if (idx >= 0) {
          final desiredId = cs.all[idx].id;
          if (cs.selectedId != desiredId) {
            ref.read(currencyProvider.notifier).select(desiredId);
          }
        }
        _activeCurrency = serverActive;
      } else {
        _activeCurrency = _currencyCode(ref.read(currencyProvider));
      }
      _bootstrap();
      _restoreScrollPosition();
      _persistPurchaseFlow();
    });
  }

  @override
  void dispose() {
    _persistPurchaseFlow();
    _pageScrollController.dispose();
    _qtyFocus.dispose();
    _pinCtl.dispose();
    _fullNameCtl.dispose();
    _dealerTotalCtl.dispose();
    _customerTotalCtl.dispose();
    _quantityCtl.dispose();
    for (final c in _paramCtrls.values) {
      c.dispose();
    }
    _paramCtrls.clear();
    super.dispose();
  }

  // ───────────────────── data helpers ─────────────────────

  static String _currencyCode(CurrencyState s) {
    final chosen = s.all.firstWhere(
      (c) => c.id == s.selectedId,
      orElse: () => s.all.isNotEmpty
          ? s.all.first
          : const Currency(id: 0, code: 'USD', symbol: r'$', available: 0),
    );
    return chosen.code.trim().toUpperCase();
  }

  Map<String, dynamic>? _criteriaInfoFromProviders() {
    // 1) Explicit criteria (e.g. CV flow)
    final explicit = ref.read(onlinePurchaseCriteriaProvider);
    if (explicit != null && explicit.isNotEmpty) {
      return _sanitizeCriteriaInfoIfNeeded(explicit);
    }

    // 2) Customer-info payload (Power Ogero / Moonet / etc.)
    final info = ref.read(onlineCustomerInfoProvider);
    final d = info?.response.data;
    if (d != null && d.isNotEmpty) return _sanitizeCriteriaInfoIfNeeded(d);

    return null;
  }

  /// Remove duplicated / legacy keys for CV criteria payloads.
  ///
  /// We only sanitize when the payload is explicitly identified as CV
  /// (method == "cv" or has CV-specific keys).
  Map<String, dynamic> _sanitizeCriteriaInfoIfNeeded(Map<String, dynamic> raw) {
    final method = _pickStr(raw['method']).toLowerCase();
    final looksCv = method == 'cv' ||
        raw.containsKey('cv_option_ids') ||
        raw.containsKey('cv_master') ||
        raw.containsKey('cv_quantity');

    if (!looksCv) return raw;

    final out = <String, dynamic>{};
    // Strict, non-duplicated CV schema.
    const keys = <String>[
      'has_info',
      'method',
      'full_name',
      'cv_master',
      'cv_quantity',
      'cv_option_ids',
      'cv_option_keys',
      'cv_option_labels',
      'receiver_number',
      'cv_slaves',
      'cv_slave_count',
    ];
    for (final k in keys) {
      if (raw.containsKey(k)) out[k] = raw[k];
    }

    // Normalize receiver_number from legacy aliases (without keeping duplicates).
    final receiver = _pickStr(out['receiver_number']).isNotEmpty
        ? _pickStr(out['receiver_number'])
        : (_pickStr(raw['cv_receiver_number']).isNotEmpty
            ? _pickStr(raw['cv_receiver_number'])
            : _pickStr(raw['reciever_number']));
    if (receiver.isNotEmpty) {
      out['receiver_number'] = receiver;
      // If cv_master is missing, set it to receiver_number (common CV convention).
      if (_pickStr(out['cv_master']).isEmpty) {
        out['cv_master'] = receiver;
      }
    }

    // Ensure flags.
    out['has_info'] = true;
    out['method'] = 'cv';
    return out;
  }

  static String _pickStr(dynamic v) {
    if (v == null) return '';
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    return s;
  }

  static bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  static String _pipesToLines(String s) {
    final raw = s.trim();
    if (!raw.contains('|')) return raw;
    final parts = raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != 'null' && e != '-')
        .toList(growable: false);
    return parts.isEmpty ? raw : parts.join('\n');
  }

  int? _quantityFromCriteria(Map<String, dynamic>? c) {
    if (c == null) return null;
    // CV: cv_quantity
    // Generic: quantity/qty/qte (some flows may carry it in criteria_info)
    dynamic v = c['cv_quantity'];
    v ??= c['quantity'];
    v ??= c['Quantity'];
    v ??= c['qty'];
    v ??= c['qte'];
    if (v == null) return null;

    final n = int.tryParse(v.toString().trim());
    if (n == null || n <= 0) return null;
    return n;
  }

  String? _fullNameFromCriteria(Map<String, dynamic>? c) {
    if (c == null) return null;
    final s1 = _pickStr(c['full_name']);
    if (s1.isNotEmpty) return s1;
    final s2 = _pickStr(c['fullName']);
    return s2.isEmpty ? null : s2;
  }

  String? _fullNameFromParamsDefaults(Map<String, dynamic> d) {
    if (d.isEmpty) return null;
    final v = _pickStr(d['full_name']);
    return v.isEmpty ? null : v;
  }

  int? _quantityFromParamsDefaults(
      Map<String, dynamic> d, OnlinePurchaseOrderData data) {
    if (d.isEmpty) return null;
    dynamic v = d['quantity'];
    v ??= d['Quantity'];
    if (v == null) return null;

    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;

    final n = int.tryParse(s);
    if (n == null || n <= 0) return null;

    // If the API provides a list, only accept values that exist in that list.
    if (data.quantityValuesIsList) {
      final allowed = data.quantityValues
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty && e != 'null')
          .toSet();
      return allowed.contains(n.toString()) ? n : null;
    }

    final minQ = _minQ(data);
    final maxQ = _maxQ(data);
    return n.clamp(minQ, maxQ);
  }

  bool _isCableVisionSlaveRefillBrand(OnlinePurchaseOrderData data) {
    return data.brand.name.trim().toUpperCase() ==
        _cableVisionSlaveRefillBrandName;
  }

  bool _isSlaveQuantityParam(String paramName) {
    return paramName.trim().toUpperCase() == _slaveQuantityParamName;
  }

  String? _slaveQuantityParamKey(OnlinePurchaseOrderData data) {
    if (!_isCableVisionSlaveRefillBrand(data)) return null;

    for (final p in data.params) {
      if (_isSlaveQuantityParam(p)) return p;
    }
    for (final key in data.paramsDefaults.keys) {
      if (_isSlaveQuantityParam(key)) return key;
    }
    return null;
  }

  int _clampSlaveQuantity(dynamic rawValue) {
    final raw = rawValue?.toString().trim() ?? '';
    final parsed = int.tryParse(raw);
    final safe = parsed ?? 1;
    return safe.clamp(1, 3);
  }

  int _currentSlaveQuantity(OnlinePurchaseOrderData data) {
    final key = _slaveQuantityParamKey(data);
    if (key == null) return 1;

    final ctl = _paramCtrls[key];
    if (ctl != null && ctl.text.trim().isNotEmpty) {
      return _clampSlaveQuantity(ctl.text);
    }

    return _clampSlaveQuantity(data.paramsDefaults[key]);
  }

  int? _enteredQuantityFromInput(OnlinePurchaseOrderData data) {
    final raw = _quantityCtl.text.trim();
    if (raw.isNotEmpty) {
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 1) return null;
      return _normalizeRequestedQty(
        data,
        parsed,
        fallbackQty: _quantity > 0 ? _quantity : data.quantity,
      );
    }

    if (_quantity > 0) {
      return _normalizeRequestedQty(
        data,
        _quantity,
        fallbackQty: data.quantity,
      );
    }

    if (data.quantity > 0) {
      return _normalizeRequestedQty(
        data,
        data.quantity,
        fallbackQty: data.quantity,
      );
    }

    return null;
  }

  int? _effectiveQuantityForDisplay(OnlinePurchaseOrderData data,
      {int? originalQtyOverride}) {
    final original = originalQtyOverride ?? _enteredQuantityFromInput(data);
    if (original == null || original < 1) return null;

    if (!_isCableVisionSlaveRefillBrand(data)) {
      return original;
    }

    return original * _currentSlaveQuantity(data);
  }

  int _quantityForDisplayedPricing(OnlinePurchaseOrderData data,
      {int? originalQtyOverride}) {
    final effective = _effectiveQuantityForDisplay(
      data,
      originalQtyOverride: originalQtyOverride,
    );
    if (effective != null && effective > 0) return effective;

    final fallbackOriginal = originalQtyOverride ??
        (_quantity > 0
            ? _normalizeRequestedQty(data, _quantity, fallbackQty: data.quantity)
            : (data.quantity > 0 ? data.quantity : _minQ(data)));

    if (_isCableVisionSlaveRefillBrand(data)) {
      return fallbackOriginal * _currentSlaveQuantity(data);
    }

    return fallbackOriginal;
  }

  String _effectiveQuantityText(OnlinePurchaseOrderData data) {
    final original = _enteredQuantityFromInput(data);
    final slaveQty = _currentSlaveQuantity(data);
    final effective = _effectiveQuantityForDisplay(data);

    if (original == null || original < 1 || effective == null || effective < 1) {
      return 'Effective quantity: enter quantity ≥ 1';
    }

    return 'Effective quantity: $original × $slaveQty = $effective';
  }

  String _effectiveQuantityCompactText(OnlinePurchaseOrderData data) {
    final original = _enteredQuantityFromInput(data);
    final slaveQty = _currentSlaveQuantity(data);
    final effective = _effectiveQuantityForDisplay(data);

    if (original == null || original < 1 || effective == null || effective < 1) {
      return '—';
    }

    if (slaveQty == 1) return effective.toString();
    return '$original × $slaveQty = $effective';
  }

  void _syncDisplayedPricingControllers(OnlinePurchaseOrderData data,
      {int? originalQtyOverride}) {
    _updateUnitPricingFromOrder(data);
    _applyPricingToControllers(
      data,
      _quantityForDisplayedPricing(
        data,
        originalQtyOverride: originalQtyOverride,
      ),
    );
  }

  void _refreshDisplayedPricing(OnlinePurchaseOrderData data,
      {int? originalQtyOverride}) {
    setState(() {
      _syncDisplayedPricingControllers(
        data,
        originalQtyOverride: originalQtyOverride,
      );
    });
  }

  bool _commitQuantityForSubmit(OnlinePurchaseOrderData data) {
    if (data.disableQuantity) return true;

    final raw = _quantityCtl.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) {
      _snack('Quantity must be at least 1.', error: true);
      return false;
    }

    final normalized = _normalizeRequestedQty(
      data,
      parsed,
      fallbackQty: data.quantity > 0 ? data.quantity : _minQ(data),
    );

    _quantity = normalized;
    final normalizedText = normalized.toString();
    if (_quantityCtl.text.trim() != normalizedText) {
      _quantityCtl.text = normalizedText;
    }

    _syncDisplayedPricingControllers(
      data,
      originalQtyOverride: normalized,
    );
    _persistPurchaseFlow();
    return true;
  }

  String _historyKeyForParam(String param) {
    final key = param
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return key.isEmpty ? 'purchase.param.generic' : 'purchase.param.$key';
  }

  void _bootstrap() {
    // Pre-seed quantity/full name from criteria_info (notably CV pricing flow)
    // to avoid an initial order-preview request with quantity=1.
    final criteria = _criteriaInfoFromProviders();

    final qCrit = _quantityFromCriteria(criteria);
    if (_quantity <= 0) {
      if (qCrit != null && qCrit > 0) {
        _quantity = qCrit;
        final qs = qCrit.toString();
        if (_quantityCtl.text.trim() != qs) {
          _quantityCtl.text = qs;
        }
      } else {
        // Unknown quantity: keep it at 0 so the backend can use its minimum/default.
        _quantity = 0;
        if (_quantityCtl.text.trim().isNotEmpty) {
          _quantityCtl.clear();
        }
      }
    } else {
      final qs = _quantity.toString();
      if (_quantityCtl.text.trim() != qs) {
        _quantityCtl.text = qs;
      }
    }

    final fnCrit = _fullNameFromCriteria(criteria);
    if ((_fullNameCtl.text.trim().isEmpty) &&
        fnCrit != null &&
        fnCrit.trim().isNotEmpty) {
      _fullNameCtl.text = fnCrit.trim();
    }

    _loadOrder();
  }

  // ───────────────────── UI helpers ─────────────────────

  InputDecoration _dec({
    String? hint,
    required bool hasValue,
    bool requiredField = false,
    bool enabled = true,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: _fsLabel),
      isDense: true,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: !enabled
          ? Colors.grey.shade100
          : (requiredField && !hasValue)
              ? Colors.red.shade50
              : Colors.green.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: suffix,
    );
  }

  static num? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return num.tryParse(s);
  }

  void _updateUnitPricingFromOrder(OnlinePurchaseOrderData d) {
    // Some flows (notably CV) may carry their effective quantity in criteria_info.
    // We prefer it for unit-cost derivation to avoid mismatches when the API returns
    // a different quantity field.
    int baseQty = d.quantity;
    final method = _pickStr(d.criteriaInfo['method']).toLowerCase();
    if (method == 'cv') {
      final v = d.criteriaInfo['cv_quantity'] ?? d.criteriaInfo['quantity'];
      final n = int.tryParse((v ?? '').toString().trim());
      if (n != null && n > 0) baseQty = n;
    }

    final qty = max(1, baseQty);
    final nativeTotal = _parseNum(d.totals.totalNativeCost) ?? 0;
    _unitNativeCost = nativeTotal / qty;
    _profitPct = d.profitPercentage;
    _sellingProfitPct = d.sellingProfitPercentage;
  }

  String _dealerTotalTextFor(OnlinePurchaseOrderData d, int qty) {
    final unit = _unitNativeCost ?? 0;
    final native = unit * max(1, qty);
    if (_profitPct > 0) {
      final dealer = native * (1 + (_profitPct / 100.0));
      return MoneyFormat.format(dealer, currencyCode: d.currency);
    }
    final fallback = _parseNum(d.totals.totalDealer);
    if (fallback != null) {
      final baseQty = max(1, d.quantity);
      final unitDealer = fallback / baseQty;
      return MoneyFormat.format(unitDealer * max(1, qty),
          currencyCode: d.currency);
    }
    return MoneyFormat.format(native, currencyCode: d.currency);
  }

  String _customerTotalTextFor(OnlinePurchaseOrderData d, int qty) {
    final unit = _unitNativeCost ?? 0;
    final native = unit * max(1, qty);
    if (_profitPct > 0 || _sellingProfitPct > 0) {
      final dealer = native * (1 + (_profitPct / 100.0));
      final customer = dealer * (1 + (_sellingProfitPct / 100.0));
      return MoneyFormat.format(customer, currencyCode: d.currency);
    }
    final fallback = _parseNum(d.totals.totalCustomer);
    if (fallback != null) {
      final baseQty = max(1, d.quantity);
      final unitCustomer = fallback / baseQty;
      return MoneyFormat.format(unitCustomer * max(1, qty),
          currencyCode: d.currency);
    }
    return MoneyFormat.format(native, currencyCode: d.currency);
  }

  void _applyPricingToControllers(OnlinePurchaseOrderData d, int qty) {
    _dealerTotalCtl.text = _dealerTotalTextFor(d, qty);
    _customerTotalCtl.text = _customerTotalTextFor(d, qty);
  }

  int _minQ(OnlinePurchaseOrderData d) => d.quantityMin > 0 ? d.quantityMin : 1;
  int _maxQ(OnlinePurchaseOrderData d) =>
      d.quantityMax > 0 ? d.quantityMax : 999999999;

  int _normalizeRequestedQty(OnlinePurchaseOrderData d, int requestedQty,
      {int? fallbackQty}) {
    // If the API provides a list of selectable quantities, we must stick to the list.
    if (d.quantityValuesIsList) {
      final items = d.quantityValues
          .map((e) => int.tryParse(e.toString().trim()))
          .whereType<int>()
          .toList(growable: false);
      if (items.isNotEmpty) {
        if (items.contains(requestedQty)) return requestedQty;
        if (fallbackQty != null && items.contains(fallbackQty)) {
          return fallbackQty;
        }
        if (d.quantityMin > 0 && items.contains(d.quantityMin)) {
          return d.quantityMin;
        }
        return items.first;
      }
      // List flag true, but list empty => fall back to clamping.
    }

    final minQ = _minQ(d);
    final maxQ = _maxQ(d);
    return requestedQty.clamp(minQ, maxQ);
  }

  void _applyQuantityClamped(OnlinePurchaseOrderData d, int newQty,
      {bool reload = true}) {
    final minQ = _minQ(d);
    final maxQ = _maxQ(d);
    final clamped = newQty.clamp(minQ, maxQ);

    // Always reflect clamped value in the controller.
    final s = clamped.toString();
    if (_quantityCtl.text.trim() != s) {
      _quantityCtl.text = s;
    }

    if (clamped == _quantity) {
      // Still re-apply prices (covers cases where profit pct arrives later).
      _syncDisplayedPricingControllers(d, originalQtyOverride: clamped);
      setState(() {});
      return;
    }

    setState(() {
      _quantity = clamped;
      _syncDisplayedPricingControllers(d, originalQtyOverride: clamped);
    });

    if (reload) {
      _loadOrder(quantityOverride: clamped);
    }
  }

  void _applyManualQuantityFromText(OnlinePurchaseOrderData d, String raw,
      {bool reload = true}) {
    final n = int.tryParse(raw.trim());
    if (n == null) {
      // Revert to last known good quantity.
      _applyQuantityClamped(d, _quantity, reload: reload);
      return;
    }
    _applyQuantityClamped(d, n, reload: reload);
  }

  Widget _topLabel(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: _fsLabel,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  static String _prettyLabel(String raw) {
    var s = raw.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return s;
    final parts = s.split(' ');
    final titled = parts.map((p) {
      final low = p.toLowerCase();
      if (low == 'id') return 'ID';
      if (p.isEmpty) return p;
      return p[0].toUpperCase() + p.substring(1);
    }).join(' ');
    return titled;
  }

  TextInputType _paramKeyboardType(String paramName) {
    final low = paramName.toLowerCase();
    if (low.contains('phone') ||
        low.contains('mobile') ||
        low.contains('account') ||
        ContactPhonePicker.looksLikePhoneHint(paramName)) {
      return TextInputType.phone;
    }
    return TextInputType.text;
  }

  static String _fmt(String raw, String currencyCode) {
    final s = raw.trim();
    final n = num.tryParse(s);
    if (n == null) return s;
    return MoneyFormat.format(n, currencyCode: currencyCode);
  }

  Future<String?> _promptPin({String? errorText}) async {
    // Keep last entered PIN in controller (session-only), but do not show it on the page.
    final ctl = _pinCtl;

    // IMPORTANT: inside the dialog callbacks, always pop using the dialog
    // context, then navigate using the page context (after the dialog closes).
    final pageCtx = context;
    final pageRouter = GoRouter.of(pageCtx);

    return showDialog<String>(
      context: pageCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Enter PIN'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorText != null && errorText.trim().isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText.trim(),
                      style: TextStyle(
                          color: Theme.of(dialogCtx).colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: ctl,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    hintText: '4 digits',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop(null);
                // Navigate after the dialog is removed from the overlay.
                Future.microtask(() {
                  if (!mounted) return;
                  pageRouter.go(R.home);
                });
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final p = ctl.text.trim();
                if (p.length < 4) return; // keep dialog open
                Navigator.of(dialogCtx).pop(p);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmProceed({required OnlinePurchaseOrderData data}) async {
    final brandName = data.brand.cleanName.isNotEmpty
        ? data.brand.cleanName
        : data.brand.name;
    final originalQty = _enteredQuantityFromInput(data) ?? _quantity;
    final effectiveQty = _effectiveQuantityForDisplay(
      data,
      originalQtyOverride: originalQty,
    );
    final slaveQty = _currentSlaveQuantity(data);
    final currency =
        _activeCurrency ?? _currencyCode(ref.read(currencyProvider));
    final total = _customerTotalCtl.text.trim();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm purchase'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(brandName),
                const SizedBox(height: 8),
                Text(
                  _isCableVisionSlaveRefillBrand(data)
                      ? 'Quantity: $originalQty × $slaveQty = ${effectiveQty ?? '—'}'
                      : 'Quantity: $originalQty',
                ),
                if (total.isNotEmpty) Text('Total: $total $currency'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );

    return ok == true;
  }

  void _snack(String msg, {bool error = false}) {
    final m = msg.trim();
    if (m.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        content: Text(m),
      ),
    );
  }

  bool _looksLikePinError(String msg) {
    final m = msg.trim().toLowerCase();
    if (m.isEmpty) return false;
    if (!m.contains('pin')) return false;

    for (final k in const [
      'invalid',
      'incorrect',
      'wrong',
      'required',
      'verify',
      'verification',
      'not match',
      'mismatch',
    ]) {
      if (m.contains(k)) return true;
    }

    // If the backend mentions PIN at all, treat it as a PIN-related error.
    return true;
  }

  // ───────────────────── order load / submit ─────────────────────

  void _syncParamControllers(OnlinePurchaseOrderData data) {
    // Remove controllers for params that no longer exist.
    final keep = data.params.toSet();
    final toRemove = _paramCtrls.keys.where((k) => !keep.contains(k)).toList();
    for (final k in toRemove) {
      _paramCtrls[k]?.dispose();
      _paramCtrls.remove(k);
    }

    // Add missing controllers and apply restored/server defaults (once).
    for (final p in data.params) {
      final existed = _paramCtrls.containsKey(p);
      final ctl = _paramCtrls.putIfAbsent(p, () => TextEditingController());
      if (!existed) {
        ctl.addListener(_persistPurchaseFlow);
      }

      final restored = _pendingParamValues?[p];
      if (restored != null && restored.trim().isNotEmpty && ctl.text.trim().isEmpty) {
        ctl.text = restored;
      }

      final def = data.paramsDefaults[p];
      if (def != null && ctl.text.trim().isEmpty) {
        ctl.text = def.toString();
      }
    }

    _pendingParamValues = null;
  }

  Future<void> _loadOrder({int? quantityOverride}) async {
    final sel = ref.read(onlineBrandSelectionProvider);
    if (sel == null) {
      setState(() {
        _order = null;
        _error = 'No brand selected.';
        _loading = false;
      });
      return;
    }

    final currency =
        _activeCurrency ?? _currencyCode(ref.read(currencyProvider));
    final criteria = _criteriaInfoFromProviders();
    // Prefer CV quantity from criteria_info when present so we don't issue an
    // initial request with quantity=1 followed by a corrected request.
    final desiredQty =
        quantityOverride ?? _quantityFromCriteria(criteria) ?? _quantity;
    _quantity = desiredQty;

    final seq = ++_reqSeq;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await ApiService.instance.getOnlinePurchaseOrder(
        currency: currency,
        brandId: sel.brandId,
        groupSubdetailId: sel.subdetailId,
        quantity: desiredQty,
        criteriaInfo: criteria,
      );

      if (!mounted || seq != _reqSeq) return;

      final data = resp.data;
      if (data == null) {
        throw Exception(resp.error ?? resp.message);
      }

      final targetQty = (quantityOverride == null)
          ? (_quantity > 0
              ? _normalizeRequestedQty(
                  data,
                  _quantity,
                  fallbackQty: data.quantity,
                )
              : (_quantityFromParamsDefaults(data.paramsDefaults, data) ??
                  (data.quantityMin > 0 ? data.quantityMin : data.quantity)))
          : _normalizeRequestedQty(
              data,
              quantityOverride,
              fallbackQty: data.quantity,
            );

      setState(() {
        _order = data;
        _quantity = targetQty;
        _activeCurrency = data.currency.trim().toUpperCase().isEmpty
            ? currency
            : data.currency.trim().toUpperCase();
      });

      // Keep quantity field in sync (mainly for non-list quantities).
      final qStr = _quantity.toString();
      if (_quantityCtl.text != qStr) {
        _quantityCtl.text = qStr;
      }
      final fn = _fullNameFromParamsDefaults(data.paramsDefaults);
      if ((_fullNameCtl.text.trim().isEmpty) &&
          fn != null &&
          fn.trim().isNotEmpty) {
        _fullNameCtl.text = fn.trim();
      }

      _syncParamControllers(data);

      // Pricing: derive unit cost + apply profit percentages.
      _syncDisplayedPricingControllers(data, originalQtyOverride: _quantity);
      _persistPurchaseFlow();

      // If our initial requested quantity differs from the quantity we decided to display
      // (params_defaults.quantity OR quantity_min), reload once so totals match.
      // IMPORTANT: when desiredQty is 0, it means "quantity unspecified" and we rely on
      // the backend to apply its minimum/default, so we must NOT issue a second request.
      if (quantityOverride == null &&
          desiredQty > 0 &&
          desiredQty != targetQty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _loadOrder(quantityOverride: targetQty);
        });
      }
    } catch (e) {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _order = null;
        _error = e.toString();
      });
    } finally {
      if (mounted && seq == _reqSeq) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit({bool goHomeAfterSuccess = false}) async {
    if (_posting) return;

    final data = _order;
    final sel = ref.read(onlineBrandSelectionProvider);
    if (data == null || sel == null) return;

    if (!_commitQuantityForSubmit(data)) {
      return;
    }

    // Validate params
    final params = <String, String>{};
    for (final e in _paramCtrls.entries) {
      final v = e.value.text.trim();
      if (v.isEmpty) {
        _snack('Missing: ${e.key}', error: true);
        return;
      }
      params[e.key] = v;
    }

    final currency =
        _activeCurrency ?? _currencyCode(ref.read(currencyProvider));
    final usePinOnOrder = ref.read(sessionProvider).usePinOnOrder;

    // If PIN is disabled for orders, show a confirmation dialog instead.
    if (!usePinOnOrder) {
      final ok = await _confirmProceed(data: data);
      if (!mounted) return;
      if (!ok) return;
    }

    // Build criteria payload.
    // IMPORTANT: Prefer the server-returned criteria_info from the order-preview.
    // This avoids sending duplicated legacy CV keys that may exist in the brand-page provider.
    final baseCrit = (data.criteriaInfo.isNotEmpty)
        ? Map<String, dynamic>.from(data.criteriaInfo)
        : (Map<String, dynamic>.from(_criteriaInfoFromProviders() ?? const {}));

    final crit = _sanitizeCriteriaInfoIfNeeded(baseCrit);

    // Ensure full_name is up to date (without introducing extra CV aliases).
    final fullName = _fullNameCtl.text.trim();
    if (fullName.isNotEmpty) {
      crit['full_name'] = fullName;
    }

    // CV flow: keep criteria consistent and non-duplicated.
    final method = _pickStr(crit['method']).toLowerCase();
    if (method == 'cv') {
      // Prefer receiver_number coming from the required params input.
      String? receiver;
      for (final e in params.entries) {
        final k = e.key.toLowerCase();
        if (k.contains('receiver')) {
          final v = e.value.trim();
          if (v.isNotEmpty) {
            receiver = v;
            break;
          }
        }
      }
      if (receiver != null) {
        crit['receiver_number'] = receiver;
        if (crit.containsKey('cv_master')) {
          crit['cv_master'] = receiver;
        }
      }

      if (crit.containsKey('cv_quantity')) {
        crit['cv_quantity'] = _quantity.toString();
      }

      // Re-sanitize to drop any accidental duplicates and enforce the strict CV schema.
      final sanitized = _sanitizeCriteriaInfoIfNeeded(crit);
      crit
        ..clear()
        ..addAll(sanitized);
    }

    _orderUuid = _uuidV4();
    setState(() => _posting = true);

    try {
      // Submit order. If PIN is enabled, allow retries when PIN verification fails.
      OnlinePurchasePostResponse resp;

      if (usePinOnOrder) {
        OnlinePurchasePostResponse? okResp;
        String? pinErr;

        for (var attempt = 0; attempt < 5; attempt++) {
          var p = _pinCtl.text.trim();
          if (p.length < 4) {
            if (attempt > 0) _pinCtl.clear();
            final entered = await _promptPin(errorText: pinErr);
            if (!mounted) return;
            if (entered == null) return;
            p = entered.trim();
          }

          if (p.length < 4) {
            pinErr = 'PIN must be 4 digits.';
            continue;
          }

          try {
            okResp = await ApiService.instance.postOnlinePurchaseOrder(
              orderUuid: _orderUuid,
              currency: currency,
              brandId: sel.brandId,
              groupSubdetailId: sel.subdetailId,
              quantity: _quantity,
              pin: p,
              clientname: '',
              params: params,
              criteriaInfo: crit.isEmpty ? null : crit,
            );
            break;
          } catch (e) {
            final msg = e.toString().replaceFirst('Exception: ', '').trim();
            if (_looksLikePinError(msg) && attempt < 4) {
              pinErr =
                  msg.isNotEmpty ? msg : 'Incorrect PIN. Please try again.';
              _pinCtl.clear();
              continue;
            }
            rethrow;
          }
        }

        if (okResp == null) {
          _snack('PIN verification failed.', error: true);
          return;
        }

        resp = okResp;
      } else {
        resp = await ApiService.instance.postOnlinePurchaseOrder(
          orderUuid: _orderUuid,
          currency: currency,
          brandId: sel.brandId,
          groupSubdetailId: sel.subdetailId,
          quantity: _quantity,
          pin: null,
          clientname: '',
          params: params,
          criteriaInfo: crit.isEmpty ? null : crit,
        );
      }

      // Refresh current-balance ASAP.
      await ref
          .read(currentBalanceProvider.notifier)
          .refreshBalances(force: true);

      if (!mounted) return;

      await _showPurchaseSubmittedDialog(
        resp: resp,
        currency: currency,
        data: data,
        goHomeAfterSuccess: goHomeAfterSuccess,
      );

      if (!mounted) return;
      if (goHomeAfterSuccess) {
        // Clear transient state so returning to Brands starts clean.
        ref.read(onlineFlowProvider.notifier).resetAll();
        ref.read(onlineBrandSelectionProvider.notifier).state = null;
        ref.read(onlinePurchaseCriteriaProvider.notifier).state = null;
        ref.read(onlineCustomerInfoProvider.notifier).state = null;
        context.go(R.home);
      }
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  static const _dialogFg = Color(0xFF444444);
  static const _dialogFgSoft = Color(0xFF666666);

  bool _dialogDataNotEmpty(dynamic v) {
    if (v == null) return false;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return false;
      if (s == '-' || s.toLowerCase() == 'null') return false;
      if (s == '{}' || s == '[]') return false;
      return true;
    }
    if (v is Map) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true;
  }

  Map<String, dynamic> _purchaseNoteForDisplay({
    required OnlinePurchaseTransaction tx,
    required OnlinePurchaseOrderData data,
  }) {
    if (tx.note.isEmpty) return const <String, dynamic>{};

    final note = <String, dynamic>{...tx.note};

    final brandName = _pickStr(note['Brand']).isNotEmpty
        ? _pickStr(note['Brand'])
        : (data.brand.cleanName.isNotEmpty
            ? data.brand.cleanName
            : data.brand.name);
    final quantity = _pickStr(note['Quantity']).isNotEmpty
        ? _pickStr(note['Quantity'])
        : _quantity.toString();

    note.remove('Brand');
    note.remove('brand');
    note.remove('Quantity');
    note.remove('quantity');

    final merged = <String, dynamic>{
      'Brand': brandName,
      'Quantity': quantity,
    };

    for (final entry in note.entries) {
      if (_dialogDataNotEmpty(entry.value)) {
        merged[entry.key] = entry.value;
      }
    }

    return merged;
  }

  Future<void> _showPurchaseSubmittedDialog({
    required OnlinePurchasePostResponse resp,
    required String currency,
    required OnlinePurchaseOrderData data,
    required bool goHomeAfterSuccess,
  }) async {
    final tx = resp.transaction;
    final noteForDisplay = tx == null
        ? const <String, dynamic>{}
        : _purchaseNoteForDisplay(tx: tx, data: data);
    final noteText = prettyNote(noteForDisplay);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        TextStyle labelStyle() => const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _dialogFgSoft,
            );

        Widget kv(String k, String v) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 120, child: Text(k, style: labelStyle())),
                Expanded(
                  child: Text(
                    v,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _dialogFg,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final content = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Purchase submitted',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            color: _dialogFg,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Text(
                    tx?.currency.isNotEmpty == true ? tx!.currency : currency,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: _dialogFg,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              kv('Message', resp.message),
              if (tx != null) ...[
                kv('Transaction ID', tx.id.toString()),
                kv('Status', tx.status),
                kv('Client #', tx.clientnumber),
                kv('Customer price',
                    '${_fmt(tx.customerPrice, currency)} $currency'),
              ],
              if (noteForDisplay.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  'Note',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        color: _dialogFg,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: buildPrettyNoteWidget(
                    noteForDisplay,
                    baseStyle: const TextStyle(fontSize: 12, height: 1.25),
                    keyStyle: const TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

        final mq = MediaQuery.of(ctx);
        final maxDialogWidth = mq.size.width < 600
            ? (mq.size.width - 24).clamp(280.0, 520.0)
            : 760.0;

        Widget actionsBar(BoxConstraints constraints) {
          final compact = constraints.maxWidth < 360;

          Widget actionBtn({
            required VoidCallback? onPressed,
            required IconData icon,
            required String label,
          }) {
            if (compact) {
              return IconButton(
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon),
              );
            }

            return TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 12)),
            );
          }

          return Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: compact ? 2 : 4,
            runSpacing: 4,
            children: [
              if (noteText.isNotEmpty)
                actionBtn(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: noteText));
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                  icon: Icons.copy,
                  label: 'Copy',
                ),
              if (noteText.isNotEmpty)
                actionBtn(
                  onPressed: () async {
                    final ok = await shareText(
                      noteText,
                      title: tx == null
                          ? 'Purchase submitted'
                          : 'Transaction #${tx.id}',
                    );
                    if (!ctx.mounted) return;
                    if (!ok) {
                      await Clipboard.setData(ClipboardData(text: noteText));
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Copied (share not available)'),
                        ),
                      );
                    }
                  },
                  icon: Icons.share,
                  label: 'Share',
                ),
              if (noteText.isNotEmpty)
                actionBtn(
                  onPressed: () async {
                    final ok = await printText(
                      tx == null
                          ? 'Purchase submitted'
                          : 'Transaction #${tx.id}',
                      noteText,
                    );
                    if (!ctx.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Print is not available on this platform'),
                        ),
                      );
                    }
                  },
                  icon: Icons.print,
                  label: 'Print',
                ),
              if (!goHomeAfterSuccess)
                actionBtn(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Future.microtask(() {
                      if (!mounted) return;
                      context.go(R.home);
                    });
                  },
                  icon: Icons.home_outlined,
                  label: 'Home',
                ),
              actionBtn(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icons.close,
                label: goHomeAfterSuccess ? 'OK' : 'Close',
              ),
            ],
          );
        }

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: mq.size.width < 600 ? 12 : 28,
            vertical: mq.size.height < 700 ? 12 : 24,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: mq.size.width < 600 ? 280 : 520,
              maxWidth: maxDialogWidth,
              maxHeight: mq.size.height * 0.90,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: content),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) => actionsBar(constraints),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _uuidV4() {
    final r = Random.secure();
    int nextInt(int max) => r.nextInt(max);
    String hex(int v, int width) => v.toRadixString(16).padLeft(width, '0');

    final bytes = List<int>.generate(16, (_) => nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return '${hex(bytes[0], 2)}${hex(bytes[1], 2)}${hex(bytes[2], 2)}${hex(bytes[3], 2)}-'
        '${hex(bytes[4], 2)}${hex(bytes[5], 2)}-'
        '${hex(bytes[6], 2)}${hex(bytes[7], 2)}-'
        '${hex(bytes[8], 2)}${hex(bytes[9], 2)}-'
        '${hex(bytes[10], 2)}${hex(bytes[11], 2)}${hex(bytes[12], 2)}${hex(bytes[13], 2)}${hex(bytes[14], 2)}${hex(bytes[15], 2)}';
  }

  // ───────────────────── dictionary lookup ─────────────────────

  static String _pickClientName(Map<String, dynamic> row) {
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == 'clientname') {
        return (entry.value ?? '').toString().trim();
      }
    }
    return '';
  }

  Future<void> _showLookupDialog({
    required OnlinePurchaseOrderData data,
    required String dataKey,
    TextEditingController? targetCtrl,
  }) async {
    if (_lookupBusy) return;
    setState(() => _lookupBusy = true);

    List<Map<String, dynamic>>? results;
    String? fetchError;

    try {
      final username = ref.read(sessionProvider).username;
      results = await ApiService.instance.getProductDictionaryLookup(
        user: username,
        product: data.brand.product,
        dataKey: dataKey,
      );
    } catch (e) {
      fetchError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }

    if (!mounted) return;

    if (fetchError != null) {
      _snack(fetchError, error: true);
      return;
    }

    if (results == null || results.isEmpty) {
      _snack('No results found.');
      return;
    }

    final showValueCol = dataKey != 'clientname' &&
        results.any((r) => (r[dataKey]?.toString() ?? '').isNotEmpty);

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
                        Text(_prettyLabel(dataKey),
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
                    final value = showValueCol
                        ? (row[dataKey] ?? '').toString()
                        : '';
                    return ListTile(
                      dense: true,
                      title: Text(clientname,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      trailing: (showValueCol && value.isNotEmpty)
                          ? Text(value,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700))
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (clientname.isNotEmpty) {
                          _fullNameCtl.text = clientname;
                        }
                        if (value.isNotEmpty && targetCtrl != null) {
                          targetCtrl.text = value;
                        }
                        setState(() {});
                        _persistPurchaseFlow();
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

  Widget _lookupSuffixBtn({
    required OnlinePurchaseOrderData data,
    required String dataKey,
    TextEditingController? targetCtrl,
  }) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Lookup',
      icon: _lookupBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : Icon(Icons.search, size: 18, color: Colors.grey.shade600),
      onPressed: _lookupBusy
          ? null
          : () => _showLookupDialog(
                data: data,
                dataKey: dataKey,
                targetCtrl: targetCtrl,
              ),
    );
  }

  // ───────────────────── build ─────────────────────

  @override
  Widget build(BuildContext context) {
    // Riverpod: ref.listen must be inside build (not initState).
    ref.listen<int>(pageRefreshPulseProvider, (prev, next) {
      if (prev == next) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent != true) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadOrder();
      });
    });

    ref.listen<CurrencyState>(currencyProvider, (prev, next) {
      final code = _currencyCode(next);
      if (_activeCurrency == null) {
        _activeCurrency = code;
        return;
      }
      if (_activeCurrency == code) return;

      _activeCurrency = code;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent != true) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadOrder();
      });
    });

    final data = _order;

    final nextEnabled = !_posting && !_loading && _order != null;

    // Prefer returning to the exact previous location (brands tab + query params)
    // rather than a hard-coded route that may require path params.
    final backTarget = ref.watch(navHistoryProvider).previous ?? R.home;

    return PageNav(
        config: PageNavConfig(
          onBack: () => context.go(backTarget),
          showNext: true,
          nextEnabled: nextEnabled,
          onNext: nextEnabled ? () => _submit(goHomeAfterSuccess: true) : null,
        ),
        child: GridScrollContainer(
          controller: _pageScrollController,
          child: LayoutBuilder(
            builder: (context, c) {
              final isMobile = c.maxWidth < 720;
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) ...[
                    const Center(child: CircularProgressIndicator()),
                  ] else if (_error != null) ...[
                    ErrorMessage(message: _error!),
                  ] else if (data == null) ...[
                    const Center(child: Text('No order data.')),
                  ] else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              data.brand.cleanName.isNotEmpty
                                  ? data.brand.cleanName
                                  : data.brand.name,
                              style: const TextStyle(
                                fontSize: _fsHeader,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _accountDetailsBlock(data),
                            const SizedBox(height: 10),
                            _buildPurchaseInputs(data, isMobile: isMobile),
                            if (data.cvNoteJson.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                data.cvNoteJson.toString(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
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
        ));
  }

  Widget _buildPurchaseInputs(OnlinePurchaseOrderData data,
      {required bool isMobile}) {
    final leftChildren = <Widget>[];

    // Full name at the top
    final lookupDataKey =
        data.params.isNotEmpty ? data.params.first : 'clientname';
    final lookupTargetCtrl =
        data.params.isNotEmpty ? _paramCtrls[data.params.first] : null;
    leftChildren.add(
      _topLabel(
        'Full name',
        HistoryTextField(
          historyKey: 'purchase.full_name',
          controller: _fullNameCtl,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: _fsBase),
          decoration: _dec(
            hint: 'Customer name',
            hasValue: _fullNameCtl.text.trim().isNotEmpty,
            suffix: _lookupSuffixBtn(
              data: data,
              dataKey: lookupDataKey,
              targetCtrl: lookupTargetCtrl,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );

    // Params (account number / phone number, etc.)
    if (data.params.isNotEmpty) {
      for (final p in data.params) {
        final ctl = _paramCtrls.putIfAbsent(p, () {
          final c = TextEditingController();
          c.addListener(_persistPurchaseFlow);
          return c;
        });
        leftChildren.add(const SizedBox(height: 10));
        leftChildren.add(
          _topLabel(
            _prettyLabel(p),
            HistoryTextField(
              historyKey: _historyKeyForParam(p),
              controller: ctl,
              textInputAction: TextInputAction.next,
              keyboardType: _paramKeyboardType(p),
              style: const TextStyle(fontSize: _fsBase),
              decoration: _dec(
                hint: _prettyLabel(p),
                hasValue: ctl.text.trim().isNotEmpty,
                requiredField: true,
                suffix: _lookupSuffixBtn(
                  data: data,
                  dataKey: p,
                  targetCtrl: ctl,
                ),
              ),
              onChanged: (_) {
                if (_isCableVisionSlaveRefillBrand(data) &&
                    _isSlaveQuantityParam(p)) {
                  _refreshDisplayedPricing(data);
                  return;
                }
                setState(() {});
              },
            ),
          ),
        );
      }
    }

    // Quantity
    leftChildren.add(const SizedBox(height: 10));
    leftChildren.add(
      _topLabel(
        'Quantity',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _quantityWidget(data),
            const SizedBox(height: 4),
            Text(
              'Min: ${data.quantityMin}   Max: ${data.quantityMax}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
              ),
            ),
            if (_isCableVisionSlaveRefillBrand(data)) ...[
              const SizedBox(height: 4),
              Text(
                _effectiveQuantityText(data),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final left = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: leftChildren,
        ),
      ),
    );

    final right = Align(
      alignment: Alignment.topRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: _priceSummaryCard(data),
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: 12),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(flex: 5, child: left),
        const SizedBox(width: 16),
        Flexible(flex: 3, child: right),
      ],
    );
  }

  Widget _priceSummaryCard(OnlinePurchaseOrderData data) {
    final currency = data.currency.trim().toUpperCase();
    final dealerText = _dealerTotalCtl.text.trim();
    final customerText = _customerTotalCtl.text.trim();
    final hasDealerPrice = dealerText.isNotEmpty && dealerText != '—';
    final enteredQty = _enteredQuantityFromInput(data);
    final slaveQty = _currentSlaveQuantity(data);

    Widget row(String label, String value, {bool emphasize = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: emphasize ? (_fsLabel + 1) : _fsLabel,
                  fontWeight: FontWeight.w800,
                  color: Colors.red.shade700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${value.isEmpty ? '—' : value} $currency',
              style: TextStyle(
                fontSize: emphasize ? (_fsBase + 4) : _fsBase,
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
                color: Colors.green.shade800,
              ),
            ),
          ],
        ),
      );
    }

    Widget qtyInfoRow(String label, String value, {bool emphasize = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 12 : 11,
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
                color:
                    emphasize ? Colors.blueGrey.shade900 : Colors.blueGrey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prices',
                    style: TextStyle(
                      fontSize: _fsHeader,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                if (hasDealerPrice)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      _showPriceDetails
                          ? Icons.visibility
                          : Icons.visibility_off,
                      size: 18,
                      color: Colors.grey.shade700,
                    ),
                    onPressed: () {
                      setState(() => _showPriceDetails = !_showPriceDetails);
                      _persistPurchaseFlow();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (_isCableVisionSlaveRefillBrand(data)) ...[
              qtyInfoRow('Entered qty', enteredQty?.toString() ?? '—'),
              qtyInfoRow('Slave qty', slaveQty.toString()),
              qtyInfoRow(
                'Effective qty',
                _effectiveQuantityCompactText(data),
                emphasize: true,
              ),
              const Divider(height: 12),
            ],
            if (_showPriceDetails && hasDealerPrice) ...[
              row('Dealer cost', dealerText),
              const Divider(height: 12),
            ],
            row('Customer cost', customerText, emphasize: true),
          ],
        ),
      ),
    );
  }

  Widget _accountDetailsBlock(OnlinePurchaseOrderData data) {
    final sel = ref.watch(onlineBrandSelectionProvider);
    final info = ref.watch(onlineCustomerInfoProvider);
    // Only use customer-info if it matches the current selected subdetail.
    final infoData = (info != null &&
            sel != null &&
            info.groupSubdetailId == sel.subdetailId)
        ? info.response.data
        : null;

    // Criteria can contain CV receiver details (we inject them from the CV lookup).
    final crit = Map<String, dynamic>.from(
        _criteriaInfoFromProviders() ?? data.criteriaInfo);

    final type = _pickStr(crit['cv_type']).isNotEmpty
        ? _pickStr(crit['cv_type'])
        : _pickStr(infoData?['type']);

    final masterPkg = _pickStr(crit['cv_master_account_type']).isNotEmpty
        ? _pickStr(crit['cv_master_account_type'])
        : (_pickStr(infoData?['master_account_type']).isNotEmpty
            ? _pickStr(infoData?['master_account_type'])
            : _pickStr(infoData?['master_package']));

    final expiry = _pickStr(crit['cv_master_expiry_date']).isNotEmpty
        ? _pickStr(crit['cv_master_expiry_date'])
        : _pickStr(infoData?['master_expiry_date']);

    final masterPkgLines = _pipesToLines(masterPkg);

    // has_info marker (set on the brand page) allows us to show provider details
    // for non-CV flows too.
    final hasInfo = _asBool(crit['has_info']) ||
        (infoData != null && (infoData.isNotEmpty == true));

    // Build a small set of generic provider fields (Power Ogero/Moonet/etc.).
    final generalRows = <MapEntry<String, String>>[];

    void addGeneral(String label, String value) {
      final v = value.trim();
      if (v.isEmpty || v == 'null' || v == '-') return;
      generalRows.add(MapEntry(label, v));
    }

    if (hasInfo && infoData != null && infoData.isNotEmpty) {
      final acc = _pickStr(infoData['account_number']);
      final accId = _pickStr(infoData['account_id']);

      if (acc.isNotEmpty && accId.isNotEmpty && acc == accId) {
        addGeneral('Account ID', accId);
      } else {
        addGeneral('Account', acc);
        addGeneral('Account ID', accId);
      }

      addGeneral('Name', _pickStr(infoData['full_name']));
      addGeneral('Plan', _pickStr(infoData['current_plan']));
      addGeneral('Expiry', _pickStr(infoData['expiry_date']));
      addGeneral('Idle days', _pickStr(infoData['idle_days']));
      addGeneral('Invoices', _pickStr(infoData['total_invoices']));
      addGeneral('Amount', _pickStr(infoData['amount_cur']));
      addGeneral('Fees', _pickStr(infoData['fees_cur']));
      addGeneral('Total', _pickStr(infoData['total_amount_cur']));
    }

    final hasCv =
        type.isNotEmpty || masterPkgLines.isNotEmpty || expiry.isNotEmpty;
    final hasAny = hasCv || generalRows.isNotEmpty;
    if (!hasAny) return const SizedBox.shrink();

    Text row(String k, String v) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k  ',
              style: const TextStyle(
                fontSize: _fsLabel,
                fontWeight: FontWeight.w700,
                color: Colors.red,
              ),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(fontSize: _fsLabel, color: Colors.green),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16),
              SizedBox(width: 8),
              Text('ACCOUNT DETAILS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (type.isNotEmpty) row('Type', type),
          if (type.isNotEmpty &&
              (masterPkgLines.isNotEmpty || expiry.isNotEmpty))
            const SizedBox(height: 6),
          if (masterPkgLines.isNotEmpty) row('Master package', masterPkgLines),
          if (masterPkgLines.isNotEmpty && expiry.isNotEmpty)
            const SizedBox(height: 6),
          if (expiry.isNotEmpty) row('Master expiry', expiry),
          if (generalRows.isNotEmpty) ...[
            if (hasCv) const SizedBox(height: 10),
            ...generalRows.map((e) {
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: row(e.key, e.value),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _quantityWidget(OnlinePurchaseOrderData data) {
    // Only disable quantity when the server explicitly requests it.
    final qtyDisabled = data.disableQuantity;

    final minQ = _minQ(data);
    final maxQ = _maxQ(data);

    // Keep _quantity within range (do not fight user while typing).
    if (!_qtyFocus.hasFocus) {
      if (_quantity < minQ) _quantity = minQ;
      if (_quantity > maxQ) _quantity = maxQ;

      final qStr = _quantity.toString();
      if (_quantityCtl.text.trim() != qStr) {
        _quantityCtl.text = qStr;
      }
    }

    final items = data.quantityValues
        .map((e) => int.tryParse(e.toString().trim()))
        .whereType<int>()
        .toList(growable: false);

    if (qtyDisabled) {
      return TextFormField(
        enabled: false,
        controller: _quantityCtl,
        style: const TextStyle(fontSize: _fsBase),
        decoration: _dec(
          hint: 'Quantity',
          hasValue: true,
          enabled: false,
        ),
      );
    }

    // If the API provides a list of selectable quantities, use a dropdown.
    if (data.quantityValuesIsList && items.isNotEmpty) {
      if (!items.contains(_quantity)) {
        final preferred =
            (data.quantityMin > 0 && items.contains(data.quantityMin))
                ? data.quantityMin
                : items.first;
        _quantity = preferred;
        _quantityCtl.text = preferred.toString();
      }

      final effective = items.contains(_quantity) ? _quantity : items.first;
      _quantity = effective;

      return DropdownButtonFormField<int>(
        initialValue: effective,
        items: items
            .map(
              (q) => DropdownMenuItem<int>(
                value: q,
                child: Text(
                  q.toString(),
                  style: const TextStyle(fontSize: _fsBase),
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (v) {
          if (v == null) return;
          _applyQuantityClamped(data, v, reload: true);
        },
        decoration: _dec(
          hint: 'Select quantity',
          hasValue: true,
          requiredField: true,
        ),
      );
    }

    // Otherwise, allow manual numeric quantity within min/max.
    final current = _quantityCtl.text.trim();
    final n = int.tryParse(current);
    final inRange = n != null && n >= minQ && n <= maxQ;

    return Focus(
      focusNode: _qtyFocus,
      onFocusChange: (hasFocus) {
        if (!hasFocus) {
          _applyManualQuantityFromText(data, _quantityCtl.text, reload: true);
        }
      },
      child: TextFormField(
        controller: _quantityCtl,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: _fsBase),
        decoration: _dec(
          hint: 'Quantity',
          hasValue: inRange,
          requiredField: true,
        ),
        onChanged: (_) {
          _refreshDisplayedPricing(data);
        },
        onFieldSubmitted: (v) =>
            _applyManualQuantityFromText(data, v, reload: true),
        onEditingComplete: () {
          _applyManualQuantityFromText(data, _quantityCtl.text, reload: true);
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }
}
