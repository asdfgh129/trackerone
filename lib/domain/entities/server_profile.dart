import '../failures.dart';

/// 服务器档案：一个地址同时描述 REST/WebSocket 与位置上报入口。
///
/// Traccar 默认端口：
/// - Web / REST / WebSocket：8082（反代后通常 443）
/// - OsmAnd 位置上报：5055
class ServerProfile {
  const ServerProfile({
    required this.name,
    required this.apiBaseUrl,
    required this.reportUrl,
    this.allowSelfSigned = false,
    this.preset = false,
  });

  final String name;

  /// REST / WebSocket 根地址，不带结尾斜杠。
  final String apiBaseUrl;

  /// OsmAnd 位置上报地址。
  final String reportUrl;

  /// 是否允许自签名证书。仅在用户显式确认风险后开启。
  final bool allowSelfSigned;

  /// 是否内置演示服务器。
  final bool preset;

  /// 稳定标识：登录 Token 与本地缓存按此隔离。
  String get id => normalizeUrl(apiBaseUrl);

  bool get isSecure => apiBaseUrl.startsWith('https://');

  /// 从单个地址推导 API 与上报地址。
  ///
  /// 规则见 docs/01-prd.md AUTH-02：
  /// 1. 未写协议时默认补 `https://`；
  /// 2. `:8082` / 无端口 / 标准端口 → 上报使用 `:5055`；
  /// 3. 用户显式给了其他端口 → 上报沿用该端口；
  /// 4. 反代路径保留在 API 地址中，上报地址只保留 scheme + host。
  factory ServerProfile.fromInput(
    String name,
    String input, {
    String? reportUrl,
    bool allowSelfSigned = false,
    bool preset = false,
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidRequest,
        '请输入服务器地址',
        messageKey: 'errorServerAddressRequired',
      );
    }

    final withScheme =
        trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        trimmed.contains(RegExp(r'\s'))) {
      throw const AppFailure(
        FailureKind.invalidRequest,
        '服务器地址格式不正确，例如 https://track.example.com',
        messageKey: 'errorServerAddressFormat',
      );
    }

    final api = _stripQueryAndFragment(
      uri.replace(fragment: '', query: '').toString(),
    );
    final apiBaseUrl = api.endsWith('/') ? api.substring(0, api.length - 1) : api;

    final String report;
    if (reportUrl != null && reportUrl.trim().isNotEmpty) {
      final reportUri = Uri.tryParse(
        reportUrl.trim().contains('://')
            ? reportUrl.trim()
            : '${uri.scheme}://${reportUrl.trim()}',
      );
      if (reportUri == null || reportUri.host.isEmpty) {
        throw const AppFailure(
          FailureKind.invalidRequest,
          '上报地址格式不正确',
          messageKey: 'errorReportUrlFormat',
        );
      }
      report = _stripQueryAndFragment(
        reportUri.replace(fragment: '', query: '').toString(),
      );
    } else {
      final explicitPort = uri.hasPort ? uri.port : null;
      final isDefaultApiPort = explicitPort == null ||
          explicitPort == 80 ||
          explicitPort == 443 ||
          explicitPort == 8082;
      final reportPort = isDefaultApiPort ? 5055 : explicitPort;
      report = _stripQueryAndFragment(
        uri
            .replace(
              port: reportPort,
              path: '',
              query: '',
              fragment: '',
            )
            .toString(),
      );
    }

    return ServerProfile(
      name: name.trim().isEmpty ? uri.host : name.trim(),
      apiBaseUrl: apiBaseUrl,
      reportUrl: report.endsWith('/')
          ? report.substring(0, report.length - 1)
          : report,
      allowSelfSigned: allowSelfSigned,
      preset: preset,
    );
  }

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      name: json['name'] as String? ?? '',
      apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
      reportUrl: json['reportUrl'] as String? ?? '',
      allowSelfSigned: json['allowSelfSigned'] as bool? ?? false,
      preset: json['preset'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'apiBaseUrl': apiBaseUrl,
        'reportUrl': reportUrl,
        'allowSelfSigned': allowSelfSigned,
        'preset': preset,
      };

  ServerProfile copyWith({
    String? name,
    String? apiBaseUrl,
    String? reportUrl,
    bool? allowSelfSigned,
    bool? preset,
  }) {
    return ServerProfile(
      name: name ?? this.name,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      reportUrl: reportUrl ?? this.reportUrl,
      allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
      preset: preset ?? this.preset,
    );
  }

  /// `Uri.replace(query: '', fragment: '')` 会留下 `?` / `#`，
  /// 这里手动去掉查询串与片段，避免地址里出现多余字符。
  static String _stripQueryAndFragment(String url) {
    var end = url.length;
    final query = url.indexOf('?');
    if (query >= 0 && query < end) end = query;
    final fragment = url.indexOf('#');
    if (fragment >= 0 && fragment < end) end = fragment;
    return url.substring(0, end);
  }

  /// 归一化 URL：用于生成稳定 id。
  static String normalizeUrl(String value) {
    final trimmed = value.trim();
    final withScheme =
        trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return trimmed.toLowerCase();
    final isDefaultPort = (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    final normalized = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort && !isDefaultPort ? uri.port : null,
      path: uri.path == '/' ? '' : uri.path,
    );
    return normalized.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ServerProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServerProfile($name, $apiBaseUrl)';
}
