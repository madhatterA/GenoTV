import 'package:contracts/contracts.dart';

/// State of one provider row in [PlaySourceScreen]'s provider list.
enum UiProviderState { idle, loading, ready, failed }

/// One provider row: caller-supplied display data only, no repository or
/// resolving logic (`ui_media.dart` header rule).
class UiProviderOption {
  const UiProviderOption({
    required this.id,
    required this.name,
    required this.state,
    this.message,
    this.progress,
  });

  final String id;
  final String name;
  final UiProviderState state;

  /// Shown under the provider name — e.g. a failure reason or an
  /// auth-required prompt such as "MovieJavan login is not set up yet.".
  final String? message;

  /// 0..1 while loading, for a provider that reports how far along it is
  /// (Playtorrio Direct: sites answered); null shows the plain orb.
  final double? progress;
}

/// The stream list panel's state, driven entirely by the caller.
sealed class UiStreamList {
  const UiStreamList();
}

/// No provider has been picked yet.
class UiStreamListNone extends UiStreamList {
  const UiStreamListNone();
}

class UiStreamListLoading extends UiStreamList {
  const UiStreamListLoading({this.progress});

  /// 0..1 when the provider reports progress; null shows the plain orb.
  final double? progress;
}

class UiStreamListFailed extends UiStreamList {
  const UiStreamListFailed(this.message);

  final String message;
}

class UiStreamListReady extends UiStreamList {
  const UiStreamListReady(this.streams);

  final List<SourceSpec> streams;
}
