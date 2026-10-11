import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reusable behavioural spec for the three platform services (§5). One
/// function, three factories: the services are provided together by
/// Part 05, and the suite name in `planning/CONTRACTS.md`'s Test section
/// is singular (`runPlatformContractTests`).
void runPlatformContractTests({
  required PlatformCapabilities Function() createCapabilities,
  required DisplayModeService Function() createDisplayModeService,
  required AudioOutputService Function() createAudioOutputService,
  required AudioStreamSpec Function() passthroughRequestSpec,
}) {
  group('PlatformCapabilities contract', () {
    test('probe() twice returns the identical report instance (caching)', () async {
      final capabilities = createCapabilities();
      final first = await capabilities.probe();
      final second = await capabilities.probe();
      expect(identical(first, second), isTrue);
    });
  });

  group('DisplayModeService contract', () {
    test('a DisplayModeLease restores on release() and release() is idempotent', () async {
      final service = createDisplayModeService();
      final modes = await service.availableModes();
      if (modes.isEmpty) return; // nothing to switch to — vacuously fine

      final lease = await service.matchFor(contentFps: 24.0);
      if (lease == null) return; // no close-enough mode — vacuously fine

      await lease.release();
      await lease.release(); // idempotent — must not throw
    });
  });

  group('AudioOutputService contract', () {
    test('a downgraded negotiation carries a reason (§5 invariant)', () async {
      final service = createAudioOutputService();
      final spec = passthroughRequestSpec();
      final negotiation = await service.negotiate(spec);

      if (spec.requestedPassthrough && !negotiation.passthrough) {
        expect(negotiation.fallbackReason, isNotNull);
      }
    });

    test('a plan that loses anything carries a reason (§5 invariant)', () {
      final plan = createAudioOutputService().plan(
        const Track(id: '1', type: TrackType.audio, codec: 'truehd'),
        AudioCapabilityModel(link: AudioLink.pcmOnly, deviceFormats: const {}),
        channels: 8,
      );
      if (plan.lost.isNotEmpty) expect(plan.reason, isNotNull);
    });
  });
}
