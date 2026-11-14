/// 领域层可展示的错误。
///
/// 网络层（Dio）只在边界处转换为 [AppFailure]，UI 不直接依赖 DioException。
enum FailureKind {
  /// 无法连接、DNS 失败、连接被拒绝。
  network,

  /// 连接或读取超时。
  timeout,

  /// 401：凭证错误或 Token 失效。
  unauthorized,

  /// 403：无权限。
  forbidden,

  /// 404：资源或接口不存在。
  notFound,

  /// 400：请求参数不合法。重试无意义，应提示用户修正输入。
  invalidRequest,

  /// TLS / 证书错误。
  tls,

  /// 5xx：服务端错误。
  server,

  /// 返回结构不是 Traccar API。
  invalidServer,

  /// 需要用户先完成某项授权（例如后台定位单独同意）。
  consentRequired,

  /// 其他未知错误。
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(
    this.kind,
    this.message, {
    this.statusCode,
    this.cause,
    this.messageKey,
    this.messageArgs = const {},
  });

  final FailureKind kind;

  /// 中文兜底文案。界面优先使用 [messageKey] 对应的本地化文案。
  final String message;

  final int? statusCode;
  final Object? cause;

  /// 本地化 key（对应 ARB 中的 `error*` 条目），为空时使用 [message]。
  final String? messageKey;

  /// 本地化文案里的占位符参数。
  final Map<String, String> messageArgs;

  bool get isUnauthorized => kind == FailureKind.unauthorized;

  /// 网络类错误可以重试；凭证/权限类错误不应自动重试。
  bool get isRetryable =>
      kind == FailureKind.network ||
      kind == FailureKind.timeout ||
      kind == FailureKind.server;

  @override
  String toString() => 'AppFailure($kind, $message, status=$statusCode)';
}
