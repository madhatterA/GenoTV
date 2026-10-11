import 'package:contracts/contracts.dart';

final class ContentSourceFailure extends ProviderFailure {
  const ContentSourceFailure._(String code, String message, {super.cause})
    : super(code: code, message: message);

  const ContentSourceFailure.authRequired([
    String message = 'Log in to this provider first.',
    Object? cause,
  ]) : this._('provider.auth_required', message, cause: cause);
  const ContentSourceFailure.notFound([
    String message = 'This title was not found.',
    Object? cause,
  ]) : this._('provider.not_found', message, cause: cause);
  const ContentSourceFailure.network([Object? cause])
    : this._(
        'provider.network',
        'The provider cannot be reached right now.',
        cause: cause,
      );
  const ContentSourceFailure.invalidResponse([Object? cause])
    : this._(
        'provider.invalid_response',
        'The provider returned an unreadable response.',
        cause: cause,
      );
  const ContentSourceFailure.unavailable([Object? cause])
    : this._(
        'provider.unavailable',
        'The provider is unavailable right now.',
        cause: cause,
      );
}
