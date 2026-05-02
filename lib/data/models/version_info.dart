class VersionInfo {
  final String apiVersion;
  final String guiVersion;
  final String webVersion;
  final String? storeUrl;
  final String? androidStoreUrl;
  final String? iosStoreUrl;
  final String? updateMessage;

  const VersionInfo({
    required this.apiVersion,
    required this.guiVersion,
    required this.webVersion,
    this.storeUrl,
    this.androidStoreUrl,
    this.iosStoreUrl,
    this.updateMessage,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    // Support both snake_case and camelCase, and tolerate wrapping in {data:{...}}.
    Map<String, dynamic> src = json;
    final data = json['data'];
    if (data is Map<String, dynamic>) src = data;

    String _s(dynamic v) {
      final out = v?.toString().trim() ?? '';
      return out.isEmpty ? '' : out;
    }

    final api = _s(src['api_version'] ?? src['apiVersion']);
    final gui = _s(src['gui_version'] ?? src['guiVersion']);
    final web = _s(src['web_version'] ?? src['webVersion']);

    return VersionInfo(
      apiVersion: api.isEmpty ? '-' : api,
      guiVersion: gui.isEmpty ? '-' : gui,
      webVersion: web.isEmpty ? '-' : web,
      storeUrl: _s(src['store_url'] ?? src['storeUrl']),
      androidStoreUrl: _s(src['android_store_url'] ?? src['androidStoreUrl']),
      iosStoreUrl: _s(src['ios_store_url'] ?? src['iosStoreUrl']),
      updateMessage: _s(src['update_message'] ?? src['updateMessage']),
    );
  }
}
