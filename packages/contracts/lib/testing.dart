/// Reusable contract test suites — one function per contract, calling
/// `group()`/`test()` internally, so any package can run it against its own
/// implementation (fake or real) from that package's own `test/` directory.
library;

export 'testing/playback_contract.dart';
export 'testing/platform_contract.dart';
export 'testing/repository_contract.dart';
export 'testing/source_provider_contract.dart';
export 'testing/stream_source_contract.dart';
