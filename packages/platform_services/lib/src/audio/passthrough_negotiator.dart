import 'package:contracts/contracts.dart';

final class PassthroughNegotiator {
  const PassthroughNegotiator(this.service);

  final AudioOutputService service;

  Future<AudioNegotiation> negotiate(AudioStreamSpec spec) =>
      service.negotiate(spec);
}
