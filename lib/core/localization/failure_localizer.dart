import '../../domain/failures.dart';
import '../../l10n/app_localizations.dart';

/// 把 [AppFailure] 转成当前语言的提示文案。
///
/// 数据层只负责给出稳定的 `messageKey`（对应 ARB 中的 `error*` 条目），
/// 具体文案由界面层按语言解析；缺少 key 时回退到中文兜底文案。
String failureMessage(AppLocalizations l10n, AppFailure failure) {
  final key = failure.messageKey;
  if (key == null) return failure.message;

  switch (key) {
    case 'errorInvalidCredentials':
      return l10n.errorInvalidCredentials;
    case 'errorLoginFailed':
      return l10n.errorLoginFailed;
    case 'errorSessionExpired':
      return l10n.errorSessionExpired;
    case 'errorNoToken':
      return l10n.errorNoToken;
    case 'errorTokenMissing':
      return l10n.errorTokenMissing;
    case 'errorInvalidSession':
      return l10n.errorInvalidSession;
    case 'errorMalformedSession':
      return l10n.errorMalformedSession;
    case 'errorMalformedEvent':
      return l10n.errorMalformedEvent;
    case 'errorDeviceCreateFailed':
      return l10n.errorDeviceCreateFailed;
    case 'errorTimeout':
      return l10n.errorTimeout;
    case 'errorTls':
      return l10n.errorTls;
    case 'errorNetwork':
      return l10n.errorNetwork;
    case 'errorForbidden':
      return l10n.errorForbidden;
    case 'errorNotFound':
      return l10n.errorNotFound;
    case 'errorInvalidRequest':
      return l10n.errorInvalidRequest;
    case 'errorServer':
      return l10n.errorServer(failure.messageArgs['status'] ?? '');
    case 'errorUnrecognizedResponse':
      return l10n.errorUnrecognizedResponse;
    case 'errorRequestFailed':
      return l10n.errorRequestFailed(
        failure.messageArgs['reason'] ?? failure.message,
      );
    case 'errorNotTraccar':
      return l10n.errorNotTraccar;
    case 'errorMalformedResponse':
      return l10n.errorMalformedResponse;
    case 'errorServerRequired':
      return l10n.errorServerRequired;
    case 'errorLoginRequired':
      return l10n.errorLoginRequired;
    case 'errorServerAddressRequired':
      return l10n.errorServerAddressRequired;
    case 'errorServerAddressFormat':
      return l10n.errorServerAddressFormat;
    case 'errorReportUrlFormat':
      return l10n.errorReportUrlFormat;
    case 'errorDeleteAccountSessionExpired':
      return l10n.errorDeleteAccountSessionExpired;
    case 'errorLocationPermission':
      return l10n.errorLocationPermission;
    case 'errorPermissionsMissing':
      return l10n.errorPermissionsMissing;
    case 'errorBackgroundConsentRequired':
      return l10n.errorBackgroundConsentRequired;
    case 'errorCommandSessionExpired':
      return l10n.errorCommandSessionExpired;
    case 'errorCommandQueued':
      return l10n.errorCommandQueued;
    case 'command.requeued':
      return l10n.errorCommandRequeued;
    default:
      return failure.message;
  }
}
