import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/input_history_store.dart';
import '../utils/contact_phone_picker.dart';

class HistoryTextField extends StatefulWidget {
  final String historyKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final int maxHistoryItems;
  final bool enablePhoneContactPicker;

  const HistoryTextField({
    super.key,
    required this.historyKey,
    required this.controller,
    required this.decoration,
    this.focusNode,
    this.style,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enabled = true,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.maxHistoryItems = 8,
    this.enablePhoneContactPicker = true,
  });

  @override
  State<HistoryTextField> createState() => _HistoryTextFieldState();
}

class _HistoryTextFieldState extends State<HistoryTextField> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  OverlayEntry? _overlayEntry;
  List<String> _history = const <String>[];
  List<String> _visibleHistory = const <String>[];
  double _fieldWidth = 0;
  double _fieldHeight = 0;
  bool _isSelectingItem = false;
  bool _suppressOverlayWhileFocused = false;
  bool _isPickingContact = false;

  @override
  void initState() {
    super.initState();
    _initFocusNode(widget.focusNode);
    widget.controller.addListener(_handleTextChanged);
    _loadHistory();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureField();
      _refreshOverlay();
    });
  }

  void _initFocusNode(FocusNode? node) {
    _ownsFocusNode = node == null;
    _focusNode = node ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant HistoryTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
      _refreshVisibleHistory();
      _refreshOverlay();
    }

    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _initFocusNode(widget.focusNode);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshOverlay();
      });
    }

    if (oldWidget.historyKey != widget.historyKey) {
      _hideOverlay();
      _history = const <String>[];
      _visibleHistory = const <String>[];
      _loadHistory();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChange);
    _persistCurrentValue();
    _hideOverlay();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final values = await InputHistoryStore.load(widget.historyKey);
    if (!mounted) return;
    setState(() {
      _history = values.take(widget.maxHistoryItems).toList(growable: false);
    });
    _refreshVisibleHistory();
    _refreshOverlay();
  }

  Future<void> _persistCurrentValue() async {
    final value = widget.controller.text.trim();
    if (value.isEmpty) return;
    await InputHistoryStore.saveValue(
      widget.historyKey,
      value,
      maxItems: widget.maxHistoryItems,
    );
    if (!mounted) return;
    final values = await InputHistoryStore.load(widget.historyKey);
    if (!mounted) return;
    _history = values.take(widget.maxHistoryItems).toList(growable: false);
    _refreshVisibleHistory();
    _refreshOverlay();
  }

  void _handleTextChanged() {
    _measureField();
    _refreshVisibleHistory();
    _refreshOverlay();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _measureField();
      _refreshVisibleHistory();
      if (!_suppressOverlayWhileFocused) {
        _showOverlay();
      }
      return;
    }

    if (_isSelectingItem) {
      return;
    }

    _persistCurrentValue();
    _hideOverlay();
  }

  void _measureField() {
    final ctx = _fieldKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final size = box.size;
    _fieldWidth = size.width;
    _fieldHeight = size.height;
  }

  void _refreshVisibleHistory() {
    final q = widget.controller.text.trim().toLowerCase();
    _visibleHistory = _history.where((item) {
      final s = item.trim();
      if (s.isEmpty) return false;
      if (q.isEmpty) return true;
      return s.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  void _refreshOverlay() {
    if (!_focusNode.hasFocus ||
        !widget.enabled ||
        widget.obscureText ||
        _suppressOverlayWhileFocused ||
        _visibleHistory.isEmpty) {
      _hideOverlay();
      return;
    }

    if (_overlayEntry == null) {
      _showOverlay();
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null ||
        !_focusNode.hasFocus ||
        !widget.enabled ||
        widget.obscureText ||
        _suppressOverlayWhileFocused ||
        _visibleHistory.isEmpty) {
      return;
    }

    _overlayEntry = OverlayEntry(builder: (context) => _buildOverlay());
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _selectItem(String item) async {
    if (_isSelectingItem) return;
    _isSelectingItem = true;
    _suppressOverlayWhileFocused = true;

    try {
      widget.controller.value = TextEditingValue(
        text: item,
        selection: TextSelection.collapsed(offset: item.length),
      );
      widget.onChanged?.call(item);

      _refreshVisibleHistory();
      _hideOverlay();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });

      await _persistCurrentValue();
    } finally {
      _isSelectingItem = false;
    }
  }

  bool get _shouldShowPhoneContactPicker {
    if (!widget.enablePhoneContactPicker ||
        !widget.enabled ||
        widget.obscureText ||
        !ContactPhonePicker.isSupported) {
      return false;
    }

    return ContactPhonePicker.looksLikePhoneHint(widget.decoration.hintText) ||
        ContactPhonePicker.looksLikePhoneHint(widget.decoration.labelText) ||
        ContactPhonePicker.looksLikePhoneHint(widget.decoration.helperText);
  }

  InputDecoration _effectiveDecoration() {
    if (!_shouldShowPhoneContactPicker) return widget.decoration;

    final contactButton = IconButton(
      tooltip: 'Choose from contacts',
      visualDensity: VisualDensity.compact,
      icon: _isPickingContact
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.contacts_outlined),
      onPressed: _isPickingContact ? null : _pickPhoneFromContacts,
    );

    final existingSuffix = widget.decoration.suffixIcon;
    if (existingSuffix == null) {
      return widget.decoration.copyWith(suffixIcon: contactButton);
    }

    return widget.decoration.copyWith(
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          existingSuffix,
          contactButton,
        ],
      ),
    );
  }

  Future<void> _pickPhoneFromContacts() async {
    if (_isPickingContact) return;

    _hideOverlay();
    _suppressOverlayWhileFocused = true;
    setState(() => _isPickingContact = true);

    try {
      final picked = await ContactPhonePicker.pickPhoneNumber();
      if (!mounted || picked == null || picked.phoneNumber.trim().isEmpty) {
        return;
      }

      final phone = picked.phoneNumber.trim();
      widget.controller.value = TextEditingValue(
        text: phone,
        selection: TextSelection.collapsed(offset: phone.length),
      );
      widget.onChanged?.call(phone);
      _refreshVisibleHistory();
      await _persistCurrentValue();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not open contacts on this device.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isPickingContact = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _suppressOverlayWhileFocused = false;
        if (_focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  Widget _buildOverlay() {
    final theme = Theme.of(context);
    final hasEnoughWidth = _fieldWidth > 0;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _persistCurrentValue();
                _hideOverlay();
                FocusScope.of(context).unfocus();
              },
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, _fieldHeight + 4),
            child: Material(
              elevation: 6,
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: hasEnoughWidth ? _fieldWidth : 220,
                  maxWidth: hasEnoughWidth ? _fieldWidth : 320,
                  maxHeight: 220,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  itemCount: _visibleHistory.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _visibleHistory[index];
                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {
                        _selectItem(item);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          item,
                          style: widget.style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        key: _fieldKey,
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: _effectiveDecoration(),
          style: widget.style,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofocus: widget.autofocus,
          obscureText: widget.obscureText,
          autocorrect: widget.autocorrect,
          enableSuggestions: widget.enableSuggestions,
          enabled: widget.enabled,
          inputFormatters: widget.inputFormatters,
          onChanged: (value) {
            _suppressOverlayWhileFocused = false;
            widget.onChanged?.call(value);
            _refreshVisibleHistory();
            _refreshOverlay();
          },
          onTap: () {
            _suppressOverlayWhileFocused = false;
            _refreshOverlay();
          },
          onSubmitted: (value) async {
            await _persistCurrentValue();
            widget.onSubmitted?.call(value);
          },
          onEditingComplete: () async {
            await _persistCurrentValue();
            widget.onEditingComplete?.call();
          },
        ),
      ),
    );
  }
}
