import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';


import 'player_primary_transport.dart';

/// Phone's centered -10/play/+10 cluster with "large glyphs"
/// (`evidence/part-04-rivulet/infuse-ref/ios/IMG_8298.PNG`) — no Rivulet
/// source (see `player_control_rail.dart`'s doc comment on the same
/// compact/noncompact-only gap); diameter is measured proportionally from
/// that reference, not a cited constant.
class PlayerPhonePrimaryTransport extends StatelessWidget {
  const PlayerPhonePrimaryTransport({
    required this.controller,
    required this.state,
    super.key,
  });

  final PlaybackController controller;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) => PlayerPrimaryTransport(
    controller: controller,
    state: state,
    diameter: 58,
    gap: 40,
    autofocus: true,
  );
}

/// Phone's top-right volume readout
/// (`evidence/part-04-rivulet/infuse-ref/ios/IMG_8298.PNG`: "40%" + slider +
/// speaker glyph). Top-left close/aspect/pip: close already exists as
/// `PlayerScreen`'s own back button (`_buildChrome`); aspect/pip are omitted
/// — no `PlaybackController` method exists for either.
