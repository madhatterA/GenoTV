/// A per-brand correction to what a renderer's `GetProtocolInfo` claims.
///
/// Match is a case-insensitive substring on manufacturer and, when set,
/// model name. [deny] lists MIME types the TV advertises but cannot play;
/// [allow] lists MIME types it plays but does not advertise.
class DlnaOverride {
  final String manufacturer;
  final String? model;
  final Set<String> deny;
  final Set<String> allow;

  const DlnaOverride({
    required this.manufacturer,
    this.model,
    this.deny = const {},
    this.allow = const {},
  });

  bool matches(String? maker, String? modelName) =>
      (maker ?? '').toLowerCase().contains(manufacturer.toLowerCase()) &&
      (model == null ||
          (modelName ?? '').toLowerCase().contains(model!.toLowerCase()));
}

/// Shipped override table. Entries are added only from a real renderer's
/// observed behaviour (owner device pass); none have been observed yet.
const List<DlnaOverride> dlnaOverrides = [];
