import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_env.dart';
import '../../routing/route_names.dart';

class AdminWebViewScreen extends ConsumerStatefulWidget {
  const AdminWebViewScreen({super.key});

  @override
  ConsumerState<AdminWebViewScreen> createState() => _AdminWebViewScreenState();
}

class _AdminWebViewScreenState extends ConsumerState<AdminWebViewScreen> {
  InAppWebViewController? _controller;
  bool _loading = true;

  final _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true,
  );

  // Token source: reads 'auth_token' from SharedPreferences — same key written
  // by ApiService. To source from a Riverpod provider instead, swap this
  // method body for: ref.read(sessionProvider).token (or equivalent).
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // ── Web ──────────────────────────────────────────────────────────────────
  // On Flutter Web, Dart's http.Client uses XHR. Browsers block reading
  // Set-Cookie headers from XHR responses (forbidden header), so we can't
  // inject the cookie manually. Instead we navigate the iframe directly to
  // the autologin endpoint with the token in the URL. The browser then
  // handles the Set-Cookie + redirect to /admin/ natively.
  //
  // Django view must accept GET ?token= for this path.
  //
  // NOTE: onLoadStop and evaluateJavascript do NOT work for cross-origin
  // iframes on Flutter Web (browser same-origin policy). The spinner is
  // hidden here instead, and JS injection is skipped on web.
  Future<void> _loadAdminWeb(InAppWebViewController controller) async {
    final token = await _getToken();
    if (token != null && token.isNotEmpty) {
      final url =
          '${AppEnv.adminAutologinUrl}?token=${Uri.encodeComponent(token)}';
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } else {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(AppEnv.adminBase)),
      );
    }
    // onLoadStop never fires for cross-origin iframes on Flutter Web.
    if (mounted) setState(() => _loading = false);
  }

  // ── Mobile ───────────────────────────────────────────────────────────────
  // On mobile, POST outside the WebView so we control the HTTP exchange.
  // followRedirects = false captures the 302's Set-Cookie before the browser
  // follows the redirect. We then inject the session cookie into the native
  // WebView cookie store and load /admin/ directly.
  Future<void> _loadAdminMobile(InAppWebViewController controller) async {
    final token = await _getToken();
    if (token != null && token.isNotEmpty) {
      final client = http.Client();
      try {
        final request =
            http.Request('POST', Uri.parse(AppEnv.adminAutologinUrl))
              ..followRedirects = false
              ..headers['Authorization'] = 'Bearer $token';

        final streamed = await client.send(request);
        final response = await http.Response.fromStream(streamed);

        final rawCookie = response.headers['set-cookie'] ?? '';
        final match = RegExp(r'sessionid=([^;]+)').firstMatch(rawCookie);
        if (match != null) {
          await CookieManager.instance().setCookie(
            url: WebUri(AppEnv.adminBase),
            name: 'sessionid',
            value: match.group(1)!,
            path: '/',
            isHttpOnly: true,
          );
        }
      } catch (_) {
        // Network failure — /admin/ will show Django's own login page.
      } finally {
        client.close();
      }
    }

    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppEnv.adminBase)),
    );
  }

  Future<void> _loadAdmin(InAppWebViewController controller) =>
      kIsWeb ? _loadAdminWeb(controller) : _loadAdminMobile(controller);

  @override
  Widget build(BuildContext context) {
    // Admin role gate — plug in here:
    // final session = ref.watch(sessionProvider);
    // if (!session.isAdmin) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) => context.go(R.home));
    //   return const Scaffold(body: Center(child: CircularProgressIndicator()));
    // }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Home',
          onPressed: () => context.go(R.home),
        ),
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () {
              final c = _controller;
              if (c != null) _loadAdmin(c);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: _settings,
            onWebViewCreated: (controller) {
              _controller = controller;
              _loadAdmin(controller);
            },
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _loading = true);
            },
            onLoadStop: (controller, url) async {
              try {
                // "View site" link lives in #user-tools, not #branding.
                // Also hide the " / " text node that follows it.
                await controller.evaluateJavascript(source: """
(function(){
  var tools=document.getElementById('user-tools');
  if(!tools) return;
  var links=tools.getElementsByTagName('a');
  for(var i=0;i<links.length;i++){
    if(links[i].getAttribute('href')==='/'){
      links[i].style.setProperty('display','none','important');
      if(links[i].nextSibling) links[i].nextSibling.textContent='';
    }
  }
})();
""");
              } catch (_) {}
              if (mounted) setState(() => _loading = false);
            },
            onReceivedError: (controller, request, error) {
              if (mounted) setState(() => _loading = false);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url?.toString() ?? '';
              // Allow /admin/ pages and the autologin redirect on web.
              if (url.startsWith(AppEnv.adminBase) ||
                  url.startsWith(AppEnv.adminAutologinUrl)) {
                return NavigationActionPolicy.ALLOW;
              }
              return NavigationActionPolicy.CANCEL;
            },
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
