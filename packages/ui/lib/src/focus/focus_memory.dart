import 'package:flutter/widgets.dart';

final class FocusMemory {
  final Map<String, String> _lastFocused = <String, String>{};
  final Map<String, String> _resting = <String, String>{};
  final Map<String, Map<String, FocusNode>> _nodes =
      <String, Map<String, FocusNode>>{};

  String? lastFocused(String surfaceId) => _lastFocused[surfaceId];

  void remember(String surfaceId, String itemId) {
    _lastFocused[surfaceId] = itemId;
  }

  /// Focus left [itemId] of [surfaceId].
  void leave(String surfaceId, String itemId) {
    _resting[surfaceId] = itemId;
  }

  void clear(String surfaceId) {
    _lastFocused.remove(surfaceId);
  }

  /// Cards register their node while mounted, so Up/Down can land on the item
  /// a row last had focused (DESIGN_SPEC §6.4 rule 2).
  void attach(String surfaceId, String itemId, FocusNode node) {
    (_nodes[surfaceId] ??= <String, FocusNode>{})[itemId] = node;
  }

  void detach(String surfaceId, String itemId, FocusNode node) {
    final surface = _nodes[surfaceId];
    if (surface?[itemId] == node) surface!.remove(itemId);
  }

  /// The mounted node of the item [surfaceId] last released focus from: when a
  /// vertical move has just landed somewhere in a row, this is the item the
  /// row remembered (the landing itself has not released anything yet).
  FocusNode? restingNode(String surfaceId) {
    final id = _resting[surfaceId];
    return id == null ? null : _nodes[surfaceId]?[id];
  }
}
