import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_cache_manager.dart';
import '../../app/app_env.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../state/currency_provider.dart';
import '../../state/session_provider.dart';
import '../../utils/notify.dart';
import '../../utils/pick_avatar.dart';
import '../../widgets/grid_scroll_container.dart';
import '../../widgets/page_action_bar.dart' show PageActions, PageAction;


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _usernameCtl = TextEditingController();
  final _firstCtl = TextEditingController();
  final _lastCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _bioCtl = TextEditingController();
  final _pinCtl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _me;

  String? _selectedCurrencyCode;
  int? _uiVersion;
  bool _usePinOnOrder = true;
  bool _hideDealerPrice = false;

  bool _pinVisible = false;
  PickedAvatarFile? _pendingAvatar;

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
  }

  @override
  void dispose() {
    _usernameCtl.dispose();
    _firstCtl.dispose();
    _lastCtl.dispose();
    _emailCtl.dispose();
    _phoneCtl.dispose();
    _bioCtl.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  // ───────────────────────────── parsing helpers ─────────────────────────────

  String? _absMediaUrl(String? avatar) {
    if (avatar == null || avatar.trim().isEmpty) return null;
    final v = avatar.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    // API returns "/media/..." → make absolute using base (…/api/ → /)
    final root = AppEnv.base.replaceFirst(RegExp(r'/api/?$'), '/');
    return '$root${v.replaceFirst(RegExp(r'^/'), '')}';
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map<String, dynamic>) ? v : const <String, dynamic>{};
  String _s(dynamic v) => v?.toString().trim() ?? '';

  String _pickFirstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = _s(v);
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  Map<String, dynamic> _userMap(Map<String, dynamic> me) {
    final u = me['user'];
    if (u is Map<String, dynamic>) return u;
    return me;
  }

  Map<String, dynamic> _profileMap(Map<String, dynamic> me) => _asMap(me['profile']);

  String _username(Map<String, dynamic> me) =>
      _pickFirstNonEmpty([_userMap(me)['username'], me['username']]);

  String _email(Map<String, dynamic> me) =>
      _pickFirstNonEmpty([_userMap(me)['email'], me['email']]);

  String _firstName(Map<String, dynamic> me) =>
      _pickFirstNonEmpty([_userMap(me)['first_name'], me['first_name']]);

  String _lastName(Map<String, dynamic> me) =>
      _pickFirstNonEmpty([_userMap(me)['last_name'], me['last_name']]);

  String _phone(Map<String, dynamic> me) => _pickFirstNonEmpty([
        _profileMap(me)['phone_number'],
        me['phone_number'],
      ]);

  String _bio(Map<String, dynamic> me) => _pickFirstNonEmpty([
        _profileMap(me)['bio'],
        me['bio'],
      ]);

  String _pin(Map<String, dynamic> me) =>
      _pickFirstNonEmpty([_profileMap(me)['pin'], me['pin']]);

  bool _usePinOnOrderFrom(Map<String, dynamic> me) {
    final v = _profileMap(me)['use_pin_on_order'] ?? me['use_pin_on_order'];
    if (v == null) return true; // default to previous behavior
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  bool _hideDealerPriceFrom(Map<String, dynamic> me) {
    final v = _profileMap(me)['hide_dealer_price'] ?? me['hide_dealer_price'];
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  dynamic _defaultCurrencyRaw(Map<String, dynamic> me) =>
      _profileMap(me)['default_currency'] ?? me['default_currency'] ?? me['current_currency'];

  String _avatar(Map<String, dynamic> me) => _pickFirstNonEmpty([
        _profileMap(me)['avatar'],
        _profileMap(me)['avatar_url'],
        me['avatar'],
        me['avatar_url'],
      ]);

  int? _uiVersionFrom(Map<String, dynamic> me) {
    final v = _profileMap(me)['ui_version'] ?? me['ui_version'];
    if (v == null) return null;
    if (v is int) return v;
    final s = v.toString();
    return int.tryParse(s);
  }

  String _currencyCodeFromRaw(dynamic raw, List<Currency> known) {
    if (raw == null) return '';
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty || s == 'null') return '';
      // If backend returns a numeric ID as string
      final id = int.tryParse(s);
      if (id != null) {
        final m = known.where((c) => c.id == id).toList();
        if (m.isNotEmpty) return m.first.code;
      }
      // If backend returns a currency code like "LBP"/"USD"
      return s.toUpperCase();
    }
    if (raw is int) {
      final m = known.where((c) => c.id == raw).toList();
      if (m.isNotEmpty) return m.first.code;
      return raw.toString();
    }
    if (raw is Map) {
      final code = raw['name'] ?? raw['code'] ?? raw['currency'] ?? raw['symbol'];
      final s = code?.toString().trim();
      if (s != null && s.isNotEmpty) return s.toUpperCase();
      final id = raw['id'];
      if (id is int) {
        final m = known.where((c) => c.id == id).toList();
        if (m.isNotEmpty) return m.first.code;
      }
    }
    return raw.toString().trim().toUpperCase();
  }

  // ───────────────────────────── load / refresh ─────────────────────────────

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_json') ?? '';
      Map<String, dynamic>? me;
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) me = decoded;
      }

      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
        _error = null;
      });

      if (me != null) {
        _applyControllersFromMe(me);
      } else {
        _refreshFromServer(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _applyControllersFromMe(Map<String, dynamic> me) {
    final currencies = ref.read(currencyProvider).all;
    _usernameCtl.text = _username(me);
    _firstCtl.text = _firstName(me);
    _lastCtl.text = _lastName(me);
    _emailCtl.text = _email(me);
    _phoneCtl.text = _phone(me);
    _bioCtl.text = _bio(me);
    _pinCtl.text = _pin(me);
    _usePinOnOrder = _usePinOnOrderFrom(me);
    _hideDealerPrice = _hideDealerPriceFrom(me);

    final code = _currencyCodeFromRaw(_defaultCurrencyRaw(me), currencies);
    _selectedCurrencyCode = code.isEmpty
        ? (currencies.isNotEmpty ? currencies.first.code : null)
        : code;
    _uiVersion = _uiVersionFrom(me) ?? 2;
    setState(() {});
  }

  Future<void> _refreshFromServer({bool silent = false}) async {
    if (_busy) return;

    if (!silent) {
      setState(() {
        _busy = true;
        _error = null;
      });
    } else {
      _busy = true;
      _error = null;
    }

    try {
      final me = await AuthService.instance.me();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_json', jsonEncode(me));
      await ref.read(sessionProvider).afterLogin(me);

      if (!mounted) return;
      setState(() {
        _me = me;
        _busy = false;
      });

      _applyControllersFromMe(me);
      if (!silent) showServerNoticeFromLast(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      if (!silent) showCaughtError(context, e);
    } finally {
      _busy = false;
    }
  }

  // ───────────────────────────── validation / actions ─────────────────────────────

  String? _pinValidate(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // leave as-is
    if (!RegExp(r'^[0-9]{4}$').hasMatch(s)) {
      return 'PIN must be exactly 4 digits.';
    }
    return null;
  }

  Future<bool> _ensureCameraPermission() async {
  if (kIsWeb) return true;
  final status = await Permission.camera.status;
  if (status.isGranted) return true;

  final res = await Permission.camera.request();
  if (res.isGranted) return true;

  if (res.isPermanentlyDenied) {
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Camera permission required'),
        content: const Text('Please enable Camera permission in Settings to take a new avatar photo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await openAppSettings();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    return false;
  }

  if (!mounted) return false;
  showError(context, 'Camera permission was denied.');
  return false;
}

  Future<void> _pickAvatar() async {
  if (_busy) return;

  final src = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Change Avatar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Use Camera'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload / Gallery'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (src == null) return;

  // Camera still needs runtime permission on mobile.
  // Gallery selection relies on the platform picker and does not request
  // broad media-library permissions here.
  if (src == 'camera') {
    final ok = await _ensureCameraPermission();
    if (!ok) return;
  }

  try {
    final PickedAvatarFile? f =
        (src == 'camera') ? await pickAvatarFromCamera() : await pickAvatarFromGallery();

    if (f == null) {
      showError(context, 'Avatar selection was cancelled or is not supported on this platform.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _pendingAvatar = f;
    });
  } catch (e) {
    if (!mounted) return;
    showCaughtError(context, e);
  }
}


  Future<void> _showChangePasswordDialog() async {
    final oldCtl = TextEditingController();
    final newCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    bool busy = false;
    String? err;

    Future<void> submit(StateSetter setStateDlg) async {
      final oldPass = oldCtl.text;
      final newPass = newCtl.text;
      final confirm = confirmCtl.text;

      if (oldPass.isEmpty || newPass.isEmpty || confirm.isEmpty) {
        setStateDlg(() => err = 'All password fields are required.');
        return;
      }
      if (newPass != confirm) {
        setStateDlg(() => err = 'New password and confirmation do not match.');
        return;
      }
      if (newPass.length < 6) {
        setStateDlg(() => err = 'New password must be at least 6 characters.');
        return;
      }

      setStateDlg(() {
        busy = true;
        err = null;
      });

      try {
        await ApiService.instance.changePassword(oldPassword: oldPass, newPassword: newPass);
        if (!mounted) return;
        Navigator.of(context).pop();
        showServerNoticeFromLast(context);
        // Token changed; refresh profile to keep everything in sync.
        _refreshFromServer(silent: true);
      } catch (e) {
        setStateDlg(() {
          busy = false;
          err = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDlg) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (err != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          err!,
                          style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: oldCtl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Current password', isDense: true),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newCtl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'New password', isDense: true),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmCtl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirm new password', isDense: true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => submit(setStateDlg),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change'),
                ),
              ],
            );
          },
        );
      },
    );

    oldCtl.dispose();
    newCtl.dispose();
    confirmCtl.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_me == null) {
      showError(context, 'Profile not loaded yet.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final me = _me!;
    final currencies = ref.read(currencyProvider).all;

    final usernameNew = _usernameCtl.text.trim();
    final firstNew = _firstCtl.text.trim();
    final lastNew = _lastCtl.text.trim();
    final emailNew = _emailCtl.text.trim();
    final phoneNew = _phoneCtl.text.trim();
    final bioNew = _bioCtl.text.trim();
    final pinNew = _pinCtl.text.trim();
    final currencyNew = (_selectedCurrencyCode ?? '').trim().toUpperCase();
    final uiNew = _uiVersion;

    final usernameOld = _username(me);
    final firstOld = _firstName(me);
    final lastOld = _lastName(me);
    final emailOld = _email(me);
    final phoneOld = _phone(me);
    final bioOld = _bio(me);
    final pinOld = _pin(me);
    final usePinOld = _usePinOnOrderFrom(me);
    final hideDealerPriceOld = _hideDealerPriceFrom(me);
    final currencyOld = _currencyCodeFromRaw(_defaultCurrencyRaw(me), currencies);
    final uiOld = _uiVersionFrom(me);

    // Only send changed values. (Null means "no change".)
    final String? usernameToSend = (usernameNew == usernameOld) ? null : usernameNew;
    final String? firstToSend = (firstNew == firstOld) ? null : firstNew;
    final String? lastToSend = (lastNew == lastOld) ? null : lastNew;
    final String? emailToSend = (emailNew == emailOld) ? null : emailNew;
    final String? phoneToSend = (phoneNew == phoneOld) ? null : phoneNew;
    final String? bioToSend = (bioNew == bioOld) ? null : bioNew;
    final String? pinToSend = pinNew.isEmpty ? null : ((pinNew == pinOld) ? null : pinNew);
    final bool? usePinOnOrderToSend = (_usePinOnOrder == usePinOld) ? null : _usePinOnOrder;
    final bool? hideDealerPriceToSend = (_hideDealerPrice == hideDealerPriceOld) ? null : _hideDealerPrice;
    final String? currencyToSend = (currencyNew == currencyOld || currencyNew.isEmpty)
        ? null
        : currencyNew;
    final int? uiToSend = (uiNew == null || uiNew == uiOld) ? null : uiNew;

    final hasAvatar = _pendingAvatar != null;
    final hasAnyFieldChange =
        usernameToSend != null ||
            firstToSend != null ||
            lastToSend != null ||
            emailToSend != null ||
            phoneToSend != null ||
            bioToSend != null ||
            pinToSend != null ||
            usePinOnOrderToSend != null ||
            hideDealerPriceToSend != null ||
            currencyToSend != null ||
            uiToSend != null;

    if (!hasAvatar && !hasAnyFieldChange) {
      showSuccess(context, 'No changes to save.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      Map<String, dynamic> updated;

      // Backend expects multipart/form-data (JSON PATCH returns 415 Unsupported Media Type).
      // Use multipart even when no avatar is selected.
      if (hasAvatar) {
        final file = _pendingAvatar!;
        updated = await ApiService.instance.updateProfileMultipartBytes(
          username: usernameToSend,
          firstName: firstToSend,
          lastName: lastToSend,
          email: emailToSend,
          phoneNumber: phoneToSend,
          bio: bioToSend,
          pin: pinToSend,
          usePinOnOrder: usePinOnOrderToSend,
          hideDealerPrice: hideDealerPriceToSend,
          defaultCurrency: currencyToSend,
          uiVersion: uiToSend,
          avatarBytes: file.bytes,
          avatarFilename: file.name,
        );
      } else {
        updated = await ApiService.instance.updateProfileMultipartBytes(
          username: usernameToSend,
          firstName: firstToSend,
          lastName: lastToSend,
          email: emailToSend,
          phoneNumber: phoneToSend,
          bio: bioToSend,
          pin: pinToSend,
          usePinOnOrder: usePinOnOrderToSend,
          hideDealerPrice: hideDealerPriceToSend,
          defaultCurrency: currencyToSend,
          uiVersion: uiToSend,
        );
      }

      await ref.read(sessionProvider).afterLogin(updated);

      if (!mounted) return;
      setState(() {
        _me = updated;
        _busy = false;
        _pendingAvatar = null;
      });

      _applyControllersFromMe(updated);
      showServerNoticeFromLast(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      showCaughtError(context, e);
    }
  }

  // ───────────────────────────── UI ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GridScrollContainer(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final me = _me;
    final currencies = ref.watch(currencyProvider).all;
    final avatarPath = (me == null) ? '' : _avatar(me);
    final avatarAbs = _absMediaUrl(avatarPath);

    ImageProvider? net;
    if (avatarAbs != null && avatarAbs.isNotEmpty) {
      net = CachedNetworkImageProvider(avatarAbs, cacheManager: AppCacheManager.images);
    }

    ImageProvider? preview;
    final pending = _pendingAvatar;
    if (pending != null) {
      preview = MemoryImage(Uint8List.fromList(pending.bytes));
    }

    final avatarImg = preview ?? net;

    return PageActions(
      actions: [
        PageAction(label: 'Save', icon: Icons.save, onTap: () => _save()),
        PageAction(label: 'Refresh', icon: Icons.refresh, onTap: () => _refreshFromServer()),
      ],
      child: GridScrollContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null && _error!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 860;

                    final left = _ProfileLeftColumn(
                      avatarImg: avatarImg,
                      pendingAvatarName: pending?.name,
                      onPickAvatar: _pickAvatar,
                      onClearPending: pending == null
                          ? null
                          : () => setState(() => _pendingAvatar = null),
                      usernameCtl: _usernameCtl,
                      firstCtl: _firstCtl,
                      lastCtl: _lastCtl,
                      emailCtl: _emailCtl,
                      pinCtl: _pinCtl,
                      pinVisible: _pinVisible,
                      onTogglePinVisible: () => setState(() => _pinVisible = !_pinVisible),
                      currencies: currencies,
                      selectedCurrencyCode: _selectedCurrencyCode,
                      onCurrencyChanged: (v) => setState(() => _selectedCurrencyCode = v),
                      pinValidate: _pinValidate,
                      usePinOnOrder: _usePinOnOrder,
                      onUsePinOnOrderChanged: (v) =>
                          setState(() => _usePinOnOrder = v),
                      hideDealerPrice: _hideDealerPrice,
                      onHideDealerPriceChanged: (v) =>
                          setState(() => _hideDealerPrice = v),
                    );

                    final right = _ProfileRightColumn(
                      onChangePassword: _showChangePasswordDialog,
                      phoneCtl: _phoneCtl,
                      bioCtl: _bioCtl,
                      uiVersion: _uiVersion,
                      onUiVersionChanged: (v) => setState(() => _uiVersion = v),
                    );

                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          left,
                          const SizedBox(height: 14),
                          right,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 16),
                        Expanded(child: right),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _ProfileLeftColumn extends StatelessWidget {
  final ImageProvider? avatarImg;
  final String? pendingAvatarName;
  final VoidCallback onPickAvatar;
  final VoidCallback? onClearPending;

  final TextEditingController usernameCtl;
  final TextEditingController firstCtl;
  final TextEditingController lastCtl;
  final TextEditingController emailCtl;
  final TextEditingController pinCtl;

  final bool pinVisible;
  final VoidCallback onTogglePinVisible;
  final List<Currency> currencies;
  final String? selectedCurrencyCode;
  final ValueChanged<String?> onCurrencyChanged;
  final String? Function(String?) pinValidate;
  final bool usePinOnOrder;
  final ValueChanged<bool> onUsePinOnOrderChanged;
  final bool hideDealerPrice;
  final ValueChanged<bool> onHideDealerPriceChanged;

  const _ProfileLeftColumn({
    required this.avatarImg,
    required this.pendingAvatarName,
    required this.onPickAvatar,
    required this.onClearPending,
    required this.usernameCtl,
    required this.firstCtl,
    required this.lastCtl,
    required this.emailCtl,
    required this.pinCtl,
    required this.pinVisible,
    required this.onTogglePinVisible,
    required this.currencies,
    required this.selectedCurrencyCode,
    required this.onCurrencyChanged,
    required this.pinValidate,
    required this.usePinOnOrder,
    required this.onUsePinOnOrderChanged,
    required this.hideDealerPrice,
    required this.onHideDealerPriceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundImage: const AssetImage('assets/logo.png'),
              foregroundImage: avatarImg,
              onForegroundImageError: avatarImg != null ? (_, __) {} : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Change Avatar:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: onPickAvatar,
                        child: const Text('Choose File'),
                      ),
                      Text(
                        pendingAvatarName ?? 'No file chosen',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (onClearPending != null)
                        TextButton(
                          onPressed: onClearPending,
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        TextFormField(
          controller: usernameCtl,
          decoration: const InputDecoration(labelText: 'Username', isDense: true),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.isEmpty) return 'Username is required.';
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: firstCtl,
          decoration: const InputDecoration(labelText: 'First Name', isDense: true),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: lastCtl,
          decoration: const InputDecoration(labelText: 'Last Name', isDense: true),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: emailCtl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email', isDense: true),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.isEmpty) return 'Email is required.';
            if (!s.contains('@')) return 'Invalid email.';
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: pinCtl,
          keyboardType: TextInputType.number,
          obscureText: !pinVisible,
          decoration: InputDecoration(
            labelText: 'PIN',
            isDense: true,
            suffixIcon: IconButton(
              onPressed: onTogglePinVisible,
              icon: Icon(pinVisible ? Icons.visibility_off : Icons.visibility),
              tooltip: pinVisible ? 'Hide PIN' : 'Show PIN',
            ),
          ),
          validator: pinValidate,
        ),
        const SizedBox(height: 6),

        Row(
          children: [
            const Expanded(
              child: Text(
                'Use PIN on order',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: usePinOnOrder,
              onChanged: onUsePinOnOrderChanged,
            ),
          ],
        ),
        const SizedBox(height: 4),

        Row(
          children: [
            const Expanded(
              child: Text(
                'Hide dealer price',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: hideDealerPrice,
              onChanged: onHideDealerPriceChanged,
            ),
          ],
        ),
        const SizedBox(height: 10),

        DropdownButtonFormField<String>(
          value: (selectedCurrencyCode == null || selectedCurrencyCode!.isEmpty)
              ? (currencies.isNotEmpty ? currencies.first.code : null)
              : selectedCurrencyCode,
          items: currencies
              .map((c) => DropdownMenuItem<String>(
                    value: c.code,
                    child: Text(c.code),
                  ))
              .toList(),
          onChanged: onCurrencyChanged,
          decoration: const InputDecoration(labelText: 'Default Currency', isDense: true),
        ),
      ],
    );
  }
}

class _ProfileRightColumn extends StatelessWidget {
  final VoidCallback onChangePassword;
  final TextEditingController phoneCtl;
  final TextEditingController bioCtl;
  final int? uiVersion;
  final ValueChanged<int?> onUiVersionChanged;

  const _ProfileRightColumn({
    required this.onChangePassword,
    required this.phoneCtl,
    required this.bioCtl,
    required this.uiVersion,
    required this.onUiVersionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onChangePassword,
            child: const Text('Change Password'),
          ),
        ),
        const Divider(height: 8),
        const SizedBox(height: 10),

        TextFormField(
          controller: phoneCtl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile Phone', isDense: true),
        ),
        const SizedBox(height: 10),

        TextFormField(
          controller: bioCtl,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Bio', isDense: true),
        ),
        const SizedBox(height: 10),

        DropdownButtonFormField<int>(
          value: (uiVersion == 1 || uiVersion == 2) ? uiVersion : 2,
          items: const [
            DropdownMenuItem(value: 1, child: Text('1')),
            DropdownMenuItem(value: 2, child: Text('2')),
          ],
          onChanged: onUiVersionChanged,
          decoration: const InputDecoration(labelText: 'UI-Version', isDense: true),
        ),
      ],
    );
  }
}
