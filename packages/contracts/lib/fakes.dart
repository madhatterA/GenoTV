/// Controllable, deterministic fakes for every contract — hand-written, not
/// generated (a mock-generation package cannot emit a status stream on
/// command). Parts 02, 03, 04 and 05 build and test against these before
/// their own real implementations exist.
library;

export 'fakes/fake_platform_services.dart';
export 'fakes/fake_playback_controller.dart';
export 'fakes/fake_repositories.dart';
export 'fakes/fake_stream_source.dart';
export 'fakes/fake_video_surface.dart';
export 'fakes/fixture_provider_stub.dart';
