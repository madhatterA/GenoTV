import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:contracts/testing.dart';

/// Runs every contract test suite against the fakes. Green here is what
/// unblocks four parallel agents: it proves the fakes are trustworthy
/// enough to build against before the real implementations exist.
void main() {
  runStreamSourceContractTests(FakeStreamSource.new);

  runPlaybackControllerContractTests(
    FakePlaybackController.new,
    createFailing: FakePlaybackController.thatFailsOnOpen,
  );

  runPlatformContractTests(
    createCapabilities: FakePlatformCapabilities.new,
    createDisplayModeService: () => FakeDisplayModeService(
      modes: const <DisplayMode>[
        DisplayMode(width: 3840, height: 2160, refreshHz: 23.976, isCurrent: true),
      ],
    ),
    createAudioOutputService: () =>
        FakeAudioOutputService()..forcedFallbackReason = 'no passthrough-capable device',
    passthroughRequestSpec: () => const AudioStreamSpec(
      codec: 'truehd',
      channels: 8,
      sampleRate: 48000,
      bitDepth: 24,
      requestedPassthrough: true,
    ),
  );

  runProgressRepositoryContractTests(FakeProgressRepository.new);
  runFavouritesRepositoryContractTests(FakeFavouritesRepository.new);
  runNextUpRepositoryContractTests(FakeNextUpRepository.new);
  runTransportStateRepositoryContractTests(FakeTransportStateRepository.new);

  runSourceProviderContractTests(FixtureProviderStub.new);
}
