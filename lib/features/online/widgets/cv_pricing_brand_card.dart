import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/models/online_brand_payload.dart';
import '../../../data/models/online_cv_receiver_info.dart';
import '../../../services/api_service.dart';
import '../../../state/online_flow_state_provider.dart';
import '../../../widgets/error_message.dart';

/// Special CableVision (CV) pricing card.
///
/// Rendered whenever the brands API includes `cv_pricing` in the active block.
///
/// Notes (per requested behavior):
/// - We keep CV lookup + autofill (master + customer name + slaves + option auto-check).
/// - We do NOT render any “Account details” panel for CV.
/// - We include `has_info` plus receiver/master/slaves in `criteria_info` so the next step
///   (purchase page / transaction note) can render a complete CV note.
class CvPricingBrandCard extends StatefulWidget {
  final List<dynamic> cvPricing;
  final int maxSlaves;
  final String slaveCustomerPriceDay; // USD per day (string from API)

  /// Used to extract duration values from brand.quantityValues.
  final OnlineBrand? activeBrand;

  final int subdetailId;
  final OnlineCvPricingFlowState? initialState;
  final ValueChanged<OnlineCvPricingFlowState>? onStateChanged;

  /// Optional hook if you later add a backend endpoint for CV history.
  final void Function(String query)? onHistorySearch;

  /// Called when the user presses Order and validation passes.
  /// Provides a draft map you can forward to your order/purchase flow.
  final void Function(Map<String, dynamic> draft)? onOrder;

  /// When false, hides the internal "Order" button. Use page-level Next instead.
  final bool showOrderButton;

  /// Incrementing signal; when it changes, the card attempts to validate+submit (same as Order).
  final ValueListenable<int>? submitSignal;

  /// Emits current validity (for enabling/disabling page-level Next).
  final ValueChanged<bool>? onValidChanged;

  const CvPricingBrandCard({
    super.key,
    required this.cvPricing,
    required this.maxSlaves,
    required this.slaveCustomerPriceDay,
    required this.subdetailId,
    this.initialState,
    this.onStateChanged,
    this.activeBrand,
    this.onHistorySearch,
    this.onOrder,
    this.showOrderButton = true,
    this.submitSignal,
    this.onValidChanged,
  });

  @override
  State<CvPricingBrandCard> createState() => _CvPricingBrandCardState();
}

class _CvPricingBrandCardState extends State<CvPricingBrandCard> {
  final _historyCtl = TextEditingController();
  final _masterCtl = TextEditingController();
  final _customerNameCtl = TextEditingController();

  int _lastSubmitTick = 0;
  bool _lastValid = false;
  bool _validSyncQueued = false;

  ValueListenable<int>? _submitSignal;

  bool _lookupLoading = false;
  String? _lookupError;
  OnlineCvReceiverInfo? _lookupInfo;
  String _resolvedReceiverNumber = '';

  int? _days; // null until the user selects

  // option_id -> selected (mandatory options are forced true)
  final Map<int, bool> _selected = {};

  int _slaveCount = 0;
  final List<TextEditingController> _slaveSerials = [];

  double? _fxRateLbpPerUsd;
  bool _isRestoringInitialState = false;

  void _setSlaveCount(int count) {
    final target = count.clamp(0, widget.maxSlaves);

    // Reduce first (dispose extras).
    while (_slaveSerials.length > target) {
      final c = _slaveSerials.removeLast();
      c.dispose();
    }

    // Grow (add controllers + listeners).
    while (_slaveSerials.length < target) {
      final ctl = TextEditingController();
      ctl.addListener(() {
        if (!mounted || _isRestoringInitialState) return;
        setState(() {});
        _emitValid(force: true);
        _emitStateChanged();
      });
      _slaveSerials.add(ctl);
    }

    _slaveCount = target;
  }

  void _queueValidSync({bool force = false}) {
    if (_validSyncQueued && !force) return;
    _validSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validSyncQueued = false;
      if (!mounted) return;
      _emitValid(force: force);
    });
  }

  String _norm(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Find the per-option expiry info (NEW/live format only) for a catalog
  /// option. Matches on `option_name` first, then falls back to a normalized
  /// name/label match. Returns null for the OLD/cached format (no
  /// `master_options`) or a never-subscribed option.
  CvOptionInfo? _masterOptionFor(Map raw) {
    final info = _lookupInfo;
    if (info == null || info.masterOptions.isEmpty) return null;

    final rawKey =
        (raw['option_name'] ?? raw['option_key'] ?? raw['key'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (rawKey.isNotEmpty) {
      for (final o in info.masterOptions) {
        if (o.optionName.trim().toLowerCase() == rawKey) return o;
      }
    }

    final rawLabel =
        _norm((raw['option_label'] ?? raw['option_name'] ?? '').toString());
    if (rawLabel.isNotEmpty) {
      for (final o in info.masterOptions) {
        if (_norm(o.name) == rawLabel || _norm(o.optionName) == rawLabel) {
          return o;
        }
      }
    }
    return null;
  }

  /// Small trailing widget showing an option's own expiry date. Green =
  /// active, red + strikethrough = lapsed.
  Widget _expiryLabel(CvOptionInfo o, double fontSize) {
    return Text(
      o.expiryDate,
      style: TextStyle(
        fontSize: fontSize,
        color: o.active ? Colors.green.shade700 : Colors.red.shade700,
        decoration:
            o.active ? TextDecoration.none : TextDecoration.lineThrough,
      ),
    );
  }

  void _applyAccountTypeSelections(String masterAccountType) {
    final parts = masterAccountType
        .split('|')
        .map((e) => _norm(e))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return;

    for (final raw in widget.cvPricing) {
      if (raw is! Map) continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;

      final mandatory = _isMandatory(raw);
      if (mandatory) {
        _selected[id] = true;
        continue;
      }

      final label = _norm((raw['option_label'] ?? raw['option_name'] ?? '').toString());

      bool hit = false;
      for (final p in parts) {
        if (label == p || label.contains(p) || p.contains(label)) {
          hit = true;
          break;
        }
      }

      _selected[id] = hit;
    }
  }

  OnlineCvPricingFlowState _currentFlowState() {
    return OnlineCvPricingFlowState(
      subdetailId: widget.subdetailId,
      receiverNumber: _historyCtl.text,
      resolvedReceiverNumber: _resolvedReceiverNumber,
      masterSerial: _masterCtl.text,
      customerName: _customerNameCtl.text,
      days: _days,
      selectedOptions: Map<int, bool>.from(_selected),
      slaveCount: _slaveCount,
      slaveSerials: _slaveSerials.map((c) => c.text).toList(growable: false),
      lookupError: _lookupError,
      lookupInfo: _lookupInfo,
    );
  }

  void _emitStateChanged() {
    widget.onStateChanged?.call(_currentFlowState());
  }

  void _restoreInitialState() {
    final s = widget.initialState;
    if (s == null || s.subdetailId != widget.subdetailId) return;

    _isRestoringInitialState = true;
    try {
      _historyCtl.text = s.receiverNumber;
      _masterCtl.text = s.masterSerial;
      _customerNameCtl.text = s.customerName;
      _resolvedReceiverNumber = s.resolvedReceiverNumber;
      _lookupError = s.lookupError;
      _lookupInfo = s.lookupInfo;
      _days = s.days;

      for (final raw in widget.cvPricing) {
        if (raw is! Map) continue;
        final id = _asInt(raw['id']);
        if (id == null) continue;
        if (_isMandatory(raw)) {
          _selected[id] = true;
        } else {
          _selected[id] = s.selectedOptions[id] ?? false;
        }
      }

      final desiredCount = s.slaveCount < s.slaveSerials.length
          ? s.slaveSerials.length
          : s.slaveCount;
      _setSlaveCount(desiredCount);
      for (int i = 0; i < s.slaveSerials.length && i < _slaveSerials.length; i++) {
        _slaveSerials[i].text = s.slaveSerials[i];
      }
    } finally {
      _isRestoringInitialState = false;
    }
  }

  @override
  void initState() {
    super.initState();

    // Force-select mandatory options + derive an approximate FX rate if available.
    for (final raw in widget.cvPricing) {
      if (raw is! Map) continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;

      final mandatory = _isMandatory(raw);
      _selected[id] = mandatory ? true : false;

      if (_fxRateLbpPerUsd == null) {
        final usd = _asDouble(raw['customer_price_day']);
        final lbp = _asDouble(raw['customer_price_day_converted']);
        if (usd != null && usd > 0 && lbp != null && lbp > 0) {
          _fxRateLbpPerUsd = lbp / usd;
        }
      }
    }

    void onAnyChange() {
      if (_isRestoringInitialState) return;
      _emitValid(force: true);
      _emitStateChanged();
      if (!mounted) return;
      setState(() {});
    }

    _historyCtl.addListener(onAnyChange);
    _masterCtl.addListener(onAnyChange);
    _customerNameCtl.addListener(onAnyChange);

    _submitSignal = widget.submitSignal;
    if (_submitSignal != null) {
      _lastSubmitTick = _submitSignal!.value;
      _submitSignal!.addListener(_onSubmitSignal);
    }

    _restoreInitialState();

    // Emit initial validity after first layout.
    _queueValidSync(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitStateChanged();
    });
  }

  @override
  void didUpdateWidget(covariant CvPricingBrandCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.submitSignal != widget.submitSignal) {
      _submitSignal?.removeListener(_onSubmitSignal);
      _submitSignal = widget.submitSignal;
      if (_submitSignal != null) {
        _lastSubmitTick = _submitSignal!.value;
        _submitSignal!.addListener(_onSubmitSignal);
      }
    }

    if (oldWidget.subdetailId != widget.subdetailId) {
      _restoreInitialState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _emitStateChanged();
      });
    }

    _queueValidSync(force: true);
  }

  @override
  void dispose() {
    _submitSignal?.removeListener(_onSubmitSignal);
    _historyCtl.dispose();
    _masterCtl.dispose();
    _customerNameCtl.dispose();
    for (final c in _slaveSerials) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _lookupReceiverInfo() async {
    final q = _historyCtl.text.trim();
    if (q.isEmpty) {
      setState(() => _lookupError = 'Please enter a receiver number.');
      _emitStateChanged();
      return;
    }
    if (_lookupLoading) return;

    widget.onHistorySearch?.call(q);

    setState(() {
      _lookupLoading = true;
      _lookupError = null;
      _lookupInfo = null;
    });

    try {
      final OnlineCvReceiverInfoResponse resp =
          await ApiService.instance.postOnlineCvReceiverInfo(
        receiverNumber: q,
      );

      if (!mounted) return;

      if (resp.success == true && resp.data != null) {
        final d = resp.data!;
        _resolvedReceiverNumber = q;
        final master = d.master.trim();
        final fullName = d.fullName.trim();

        if (master.isNotEmpty) {
          _masterCtl.text = master;
        }
        if (fullName.isNotEmpty) {
          _customerNameCtl.text = fullName;
        }

        // Auto-check options based on the returned master account type.
        final acct = d.masterAccountType.trim();
        if (acct.isNotEmpty) {
          _applyAccountTypeSelections(acct);
        }

        // Auto-fill slaves (slave_1..slave_N) up to maxSlaves.
        final desired = d.slaves.length.clamp(0, widget.maxSlaves);
        _setSlaveCount(desired);
        for (int i = 0; i < desired; i++) {
          _slaveSerials[i].text = d.slaves[i].serial.trim();
        }

        setState(() {
          _lookupLoading = false;
          _lookupError = null;
          _lookupInfo = d;
        });
        _queueValidSync(force: true);
        _emitStateChanged();
      } else {
        final msg = (resp.error ?? resp.message).trim();
        setState(() {
          _lookupLoading = false;
          _lookupError = msg.isNotEmpty ? msg : 'Card not found.';
          _lookupInfo = null;
        });
        _queueValidSync(force: true);
        _emitStateChanged();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lookupLoading = false;
        _lookupError = e.toString().replaceFirst('Exception: ', '').trim();
        _lookupInfo = null;
      });
      _queueValidSync(force: true);
      _emitStateChanged();
    }
  }

  List<int> _durations() {
    final qv = widget.activeBrand?.quantityValues;
    if (qv == null) return const [];
    try {
      final decoded = json.decode(qv);
      if (decoded is List) {
        return decoded
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((v) => v > 0)
            .toList(growable: false);
      }
    } catch (_) {
      // ignore
    }
    return const [];
  }

  bool _isMandatory(Map o) {
    final type = (o['option_type'] ?? '').toString().toLowerCase().trim();
    final typeLabel =
        (o['option_type_label'] ?? '').toString().toLowerCase().trim();

    // Backend sometimes uses "mendatory".
    return type == 'mendatory' ||
        typeLabel == 'mendatory' ||
        type == 'mandatory' ||
        typeLabel == 'mandatory';
  }

  bool _anyOptionalSelected() {
    for (final raw in widget.cvPricing) {
      if (raw is! Map) continue;
      if (_isMandatory(raw)) continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;
      if ((_selected[id] ?? false) == true) return true;
    }
    return false;
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  int _effectiveNonSlaveDaysForOption(Map raw, int quantityDays) {
    if (quantityDays <= 0) return 0;

    final discountRule = _asInt(raw['discount_rule']) ?? 0;
    final discountDays = _asInt(raw['discount_days']) ?? 0;

    if (discountRule <= 0 || discountDays <= 0) {
      return quantityDays;
    }

    if (quantityDays < discountRule) {
      return quantityDays;
    }

    final discounted = quantityDays - discountDays;
    return discounted > 0 ? discounted : 0;
  }

  double _nonSlaveTotalUsd(int quantityDays) {
    if (quantityDays <= 0) return 0;

    double sum = 0;
    for (final raw in widget.cvPricing) {
      if (raw is! Map) continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;
      if ((_selected[id] ?? false) != true) continue;

      final perDay = _asDouble(raw['customer_price_day']) ?? 0;
      if (perDay <= 0) continue;

      final billedDays = _effectiveNonSlaveDaysForOption(raw, quantityDays);
      if (billedDays <= 0) continue;

      sum += billedDays * perDay;
    }
    return sum;
  }

  double _slavePerDayUsdRaw() {
    return _asDouble(widget.slaveCustomerPriceDay) ?? 0;
  }

  /// If ONLY mandatory option(s) are selected (no optional add-ons),
  /// then slaves are free (do not affect pricing).
  double _effectiveSlavePerDayUsd() {
    final raw = _slavePerDayUsdRaw();
    if (raw <= 0) return 0;
    return _anyOptionalSelected() ? raw : 0;
  }

  double _slaveTotalUsd(int quantityDays) {
    if (quantityDays <= 0 || _slaveCount <= 0) return 0;
    final slavePerDay = _effectiveSlavePerDayUsd();
    if (slavePerDay <= 0) return 0;
    return quantityDays * _slaveCount * slavePerDay;
  }

  double _totalUsd() {
    final masterOk = _masterCtl.text.trim().isNotEmpty;
    if (!masterOk || _days == null) return 0;
    final d = _days ?? 0;
    return _nonSlaveTotalUsd(d) + _slaveTotalUsd(d);
  }

  bool _slavesValid() {
    if (_slaveCount <= 0) return true;
    for (final c in _slaveSerials) {
      if (c.text.trim().isEmpty) return false;
    }
    return true;
  }

  bool _allMandatoryOptionsSelected() {
    for (final raw in widget.cvPricing) {
      if (raw is! Map) continue;
      if (!_isMandatory(raw)) continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;
      if ((_selected[id] ?? false) != true) return false;
    }
    return true;
  }

  String _effectiveReceiverNumber() {
    final typed = _historyCtl.text.trim();
    if (typed.isNotEmpty) return typed;
    if (_lookupInfo != null && _resolvedReceiverNumber.trim().isNotEmpty) {
      return _resolvedReceiverNumber.trim();
    }
    return '';
  }

  bool _isValidNow() {
    if (_masterCtl.text.trim().isEmpty) return false;
    if (_days == null) return false;
    if (!_allMandatoryOptionsSelected()) return false;
    if (!_slavesValid()) return false;
    if (_totalUsd() <= 0) return false;
    return true;
  }

  bool _canOrder() {
    return _isValidNow();
  }

  String _fmtMoney(num v, {int decimals = 2}) {
    final s = v.toStringAsFixed(decimals);
    final parts = s.split('.');
    final whole =
        parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return parts.length == 2 ? '$whole.${parts[1]}' : whole;
  }

  void _addSlave() {
    if (_slaveCount >= widget.maxSlaves) return;

    final ctl = TextEditingController();
    ctl.addListener(() {
      if (!mounted) return;
      setState(() {});
      _emitValid(force: true);
    });

    setState(() {
      _slaveCount += 1;
      _slaveSerials.add(ctl);
    });
    _queueValidSync(force: true);
    _emitStateChanged();
  }

  void _removeSlave() {
    if (_slaveCount <= 0) return;
    setState(() {
      _slaveCount -= 1;
      final c = _slaveSerials.removeLast();
      c.dispose();
    });
    _emitValid(force: true);
    _emitStateChanged();
  }

  List<int> _selectedOptionIds() {
    final out = <int>[];
    for (final raw in widget.cvPricing) {
      if (raw is! Map) continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;
      if ((_selected[id] ?? false) == true) out.add(id);
    }
    return out;
  }

  Map<String, List<String>> _selectedOptionMeta(List<int> ids) {
    final keys = <String>[];
    final labels = <String>[];

    for (final id in ids) {
      Map? hit;
      for (final raw in widget.cvPricing) {
        if (raw is! Map) continue;
        final rid = _asInt(raw['id']);
        if (rid != null && rid == id) {
          hit = raw;
          break;
        }
      }

      if (hit == null) continue;

      // What the backend expects for CV orders:
      // - option_name (e.g. "cv_back_to_basic") as the *key*
      // - option_label (human readable) as the label
      final rawName =
          (hit['option_name'] ?? hit['option_key'] ?? hit['key'])
              ?.toString()
              .trim();

      final label = _norm((hit['option_label'] ?? hit['label'] ?? '').toString());

      final key = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : (label.isNotEmpty ? _slugify(label) : _slugify('option_$id'));

      keys.add(key);
      labels.add(label.isNotEmpty ? label : key);
    }

    return {'keys': keys, 'labels': labels};
  }

  String _slugify(String s) {
    final lower = s.toLowerCase().trim();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }


  void _emitValid({bool force = false}) {
    final v = _canOrder();
    if (!force && v == _lastValid) return;
    _lastValid = v;
    widget.onValidChanged?.call(v);
  }

  String _firstMissingReason() {
    if (_masterCtl.text.trim().isEmpty) return 'Master serial number is required.';
    if (_days == null) return 'Duration is required.';
    if (!_slavesValid()) return 'Please fill all slave serial numbers.';
    if (_totalUsd() <= 0) return 'Selling price must be greater than 0.';
    return 'Missing required fields.';
  }

  Map<String, dynamic> _buildDraft(double totalUsd) {
    final receiver = _effectiveReceiverNumber();
    final master = _masterCtl.text.trim();
    final days = _days;
    final selectedIds = _selectedOptionIds();
    final optMeta = _selectedOptionMeta(selectedIds);
    final slaveSerials = _slaveSerials
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final fullName = (_lookupInfo?.fullName ?? _customerNameCtl.text).trim();
    final cvType = _lookupInfo?.type.trim() ?? '';
    final cvMasterAccountType = _lookupInfo?.masterAccountType.trim() ?? '';
    final cvMasterExpiryDate = _lookupInfo?.masterExpiryDate.trim() ?? '';

    final criteriaInfo = <String, dynamic>{
      'has_info': true,
      // Tag CV pricing flow explicitly so downstream screens can apply CV-specific defaults.
      'method': 'cv',
      'full_name': fullName,
      'cv_type': cvType,
      'cv_master': master,
      'cv_master_account_type': cvMasterAccountType,
      'cv_master_expiry_date': cvMasterExpiryDate,
      'cv_quantity': (days ?? '').toString(),
      'cv_option_ids': selectedIds.map((e) => e.toString()).toList(growable: false),
      'cv_option_keys': optMeta['keys'] ?? const [],
      'cv_option_labels': optMeta['labels'] ?? const [],

      // Receiver identifiers (keep common spellings for backward compatibility).
      'cv_receiver_number': receiver,
      'receiver_number': receiver,
      'reciever_number': receiver,

      // Slaves / master serials so the purchase page can build a complete CV note.
      'cv_slaves': slaveSerials,
      'cv_slave_serials': slaveSerials,
      'slave_serials': slaveSerials,
      'cv_slave_count': _slaveCount,
    };

    return <String, dynamic>{
      'receiver_number': receiver,
      'master_serial': master,
      'customer_name': _customerNameCtl.text.trim(),
      'days': days,
      'quantity': days,
      'selected_option_ids': selectedIds,
      'slave_serials': slaveSerials,
      'slave_count': _slaveCount,
      'total_usd': totalUsd,
      'criteria_info': criteriaInfo,
    };
  }

  void _trySubmit({required bool fromNext}) {
    if (!_canOrder()) {
      if (fromNext && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            content: Text(_firstMissingReason()),
          ),
        );
      }
      return;
    }

    final draft = _buildDraft(_totalUsd());
    widget.onOrder?.call(draft);
  }


  void _onSubmitSignal() {
    final now = _submitSignal?.value ?? 0;
    if (now == _lastSubmitTick) return;
    _lastSubmitTick = now;
    _trySubmit(fromNext: true);
  }


  @override
  Widget build(BuildContext context) {
    _queueValidSync(force: true);

    // Denser typography for the CV pricing flow (brand page).
    const double fsBase = 12;
    const double fsLabel = 11;
    const double fsButton = 12;

    final totalUsd = _totalUsd();

    final durations = _durations();
    final items = durations.isNotEmpty ? durations : const [30, 90, 180, 360];

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
    );

    // Some app themes render DropdownButton text in white; enforce a dark foreground
    // to match the other inputs on this card.
    final dropdownTextStyle = TextStyle(
      fontSize: fsBase,
      color: Colors.grey.shade900,
    );
    final dropdownHintStyle = TextStyle(
      fontSize: fsLabel,
      color: Colors.grey.shade700,
    );

    final reqEmptyFill = Colors.red.shade50;
    final reqOkFill = Colors.green.shade50;
    Color reqFill(bool ok) => ok ? reqOkFill : reqEmptyFill;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _historyCtl,
                    style: const TextStyle(fontSize: fsBase),
                    decoration: InputDecoration(
                      hintText: 'Receiver number...',
                      hintStyle: const TextStyle(fontSize: fsLabel),
                      isDense: true,
                      border: border,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: _lookupLoading ? null : _lookupReceiverInfo,
                    child: _lookupLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Search',
                            style: TextStyle(fontSize: fsButton),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_lookupError != null && _lookupError!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ErrorMessage(message: _lookupError!),
              ),

            // IMPORTANT: no CV account details panel here.
            // We keep _lookupInfo only for autofill and for passing into criteria_info.

            LayoutBuilder(
              builder: (context, c) {
                final isNarrow = c.maxWidth < 720;

                final f1 = SizedBox(
                  width: isNarrow ? double.infinity : 320,
                  child: TextField(
                    controller: _masterCtl,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontSize: fsBase),
                    decoration: InputDecoration(
                      labelText: 'Master Serial Number:',
                      hintText: 'required',
                      labelStyle: const TextStyle(fontSize: fsLabel),
                      hintStyle: const TextStyle(fontSize: fsLabel),
                      isDense: true,
                      border: border,
                      filled: true,
                      fillColor: reqFill(_masterCtl.text.trim().isNotEmpty),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                );

                final f2 = SizedBox(
                  width: isNarrow ? double.infinity : 320,
                  child: TextField(
                    controller: _customerNameCtl,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: fsBase),
                    decoration: InputDecoration(
                      labelText: 'Customer name:',
                      hintText: 'optional',
                      labelStyle: const TextStyle(fontSize: fsLabel),
                      hintStyle: const TextStyle(fontSize: fsLabel),
                      isDense: true,
                      border: border,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                );

                final f3 = SizedBox(
                  width: isNarrow ? double.infinity : 220,
                  child: DropdownButtonFormField<int>(
                    initialValue: _days,
                    items: items
                        .map((d) => DropdownMenuItem<int>(
                              value: d,
                              child: Text(
                                '$d',
                                style: dropdownTextStyle,
                              ),
                            ))
                        .toList(growable: false),
                    onChanged: (v) {
                      setState(() => _days = v);
                      _emitValid(force: true);
                      _emitStateChanged();
                    },
                    style: dropdownTextStyle,
                    decoration: InputDecoration(
                      labelText: 'Duration:',
                      hintText: 'Days',
                      labelStyle: const TextStyle(fontSize: fsLabel),
                      hintStyle: dropdownHintStyle,
                      isDense: true,
                      border: border,
                      filled: true,
                      fillColor: reqFill(_days != null),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                );

                return Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: [f1, f2, f3],
                );
              },
            ),

            const SizedBox(height: 10),

            // Options
            ...widget.cvPricing.map((raw) {
              if (raw is! Map) return const SizedBox.shrink();
              final id = _asInt(raw['id']);
              if (id == null) return const SizedBox.shrink();

              final label =
                  (raw['option_label'] ?? raw['option_name'] ?? '').toString();
              final mandatory = _isMandatory(raw);

              final style = TextStyle(
                fontStyle: FontStyle.italic,
                color: mandatory ? Colors.red.shade700 : Colors.green.shade700,
                fontSize: fsBase,
              );

              // Per-option expiry (NEW/live format only). Null for the
              // OLD/cached format or a never-subscribed option ⇒ nothing extra.
              final optInfo = _masterOptionFor(raw);

              // Use the same on/off control style as the Login page "Remember" switch.
              // This keeps the CV pricing option toggles visually consistent across the app.
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Switch(
                      value: _selected[id] ?? false,
                      onChanged: mandatory
                          ? null
                          : (v) {
                              setState(() => _selected[id] = v);
                              _emitValid(force: true);
                              _emitStateChanged();
                            },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: style,
                      ),
                    ),
                    if (optInfo != null && optInfo.expiryDate.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _expiryLabel(optInfo, fsLabel),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 10),

            // Slaves
            Row(
              children: [
                OutlinedButton(
                  onPressed: widget.maxSlaves > 0 && _slaveCount < widget.maxSlaves
                      ? _addSlave
                      : null,
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: fsButton),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('+ Slave'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _slaveCount > 0 ? _removeSlave : null,
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: fsButton),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('- Slave'),
                ),
              ],
            ),

            if (_slaveCount > 0) ...[
              const SizedBox(height: 10),
              ...List.generate(_slaveCount, (i) {
                // Slave fields are autofilled from _lookupInfo.slaves[i] in the
                // same order, so index maps 1:1. Per-option expiry exists in the
                // NEW/live format only; OLD/cached ⇒ empty ⇒ nothing extra.
                final slaveInfo =
                    (_lookupInfo != null && i < _lookupInfo!.slaves.length)
                        ? _lookupInfo!.slaves[i]
                        : null;
                final slaveOpts = slaveInfo?.options ?? const <CvOptionInfo>[];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _slaveSerials[i],
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          setState(() {});
                          _emitStateChanged();
                        },
                        style: const TextStyle(fontSize: fsBase),
                        decoration: InputDecoration(
                          labelText: 'Slave Serial #${i + 1}',
                          hintText: 'required',
                          labelStyle: const TextStyle(fontSize: fsLabel),
                          hintStyle: const TextStyle(fontSize: fsLabel),
                          isDense: true,
                          border: border,
                          filled: true,
                          fillColor:
                              reqFill(_slaveSerials[i].text.trim().isNotEmpty),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                      if (slaveOpts.isNotEmpty)
                        ...slaveOpts
                            .where((o) => o.expiryDate.isNotEmpty)
                            .map(
                              (o) => Padding(
                                padding:
                                    const EdgeInsets.only(left: 4, top: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o.name,
                                        style: TextStyle(
                                          fontSize: fsLabel,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _expiryLabel(o, fsLabel),
                                  ],
                                ),
                              ),
                            ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 6),

            Row(
              children: [
                const Text(
                  'Selling Price:',
                  style: TextStyle(fontSize: fsBase),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_fmtMoney(totalUsd)} USD',
                  style: const TextStyle(fontSize: fsBase),
                ),
              ],
            ),

            // Keep the single "Old Expiry Date" line for the OLD/cached format
            // (no per-option data). When per-option lines are shown above, they
            // supersede it.
            if ((_lookupInfo?.masterOptions.isEmpty ?? true) &&
                (_lookupInfo?.masterExpiryDate.trim() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    'Old Expiry Date:',
                    style: TextStyle(fontSize: fsBase),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _lookupInfo!.masterExpiryDate.trim(),
                    style: const TextStyle(fontSize: fsBase),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            // Order button (bottom)
            if (widget.showOrderButton)
              FilledButton(
                onPressed: _canOrder() ? () => _trySubmit(fromNext: false) : null,
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(fontSize: fsButton),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: const Text('Order'),
              ),
          ],
        ),
      ),
    );
  }
}
