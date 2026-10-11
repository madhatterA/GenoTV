/// Tracks a row's selected item by identity, not position.
///
/// Source: `research/Rivulet/Rivulet/Views/Media/PlexHome/UIKit/PlexHomeViewController.swift:32-37`
/// — "`UICollectionView.remembersLastFocusedIndexPath = true` keeps the last
/// focused tile in each row" and `:1310-1311` — "Its item identifier never
/// changes across snapshots" — Rivulet restores focus by the cell's stable
/// item identifier, not by index, because a row can be re-sorted or
/// paginated between focus events. This is the same rule generalized to a
/// nearest-surviving-neighbor fallback for when the exact id is gone (e.g.
/// removed from Continue Watching): step 6 of the phase file explicitly
/// forbids identifying the restoration target by mutable list index.
final class RowFocusPolicy {
  RowFocusPolicy(List<String> itemIds) : _itemIds = List<String>.of(itemIds);

  List<String> _itemIds;
  String? _selectedId;

  List<String> get itemIds => List<String>.unmodifiable(_itemIds);

  String? get selectedId => _selectedId;

  int? get selectedIndex => _selectedId == null ? null : _indexOf(_selectedId!);

  int? _indexOf(String id) {
    final index = _itemIds.indexOf(id);
    return index < 0 ? null : index;
  }

  /// Selects [id]. It must be present in the current item list.
  void select(String id) {
    assert(_itemIds.contains(id), 'select() target must be a current item');
    _selectedId = id;
  }

  /// Moves the selection one item toward [forward] and reports whether it
  /// moved. Returns false at either end instead of wrapping, so a caller at
  /// a row boundary can hand the command to the next focus scope rather
  /// than trap it.
  bool moveFocus(bool forward) {
    if (_itemIds.isEmpty) return false;
    final current = selectedIndex;
    if (current == null) {
      _selectedId = _itemIds.first;
      return true;
    }
    final next = current + (forward ? 1 : -1);
    if (next < 0 || next >= _itemIds.length) return false;
    _selectedId = _itemIds[next];
    return true;
  }

  /// Applies a new item list after insertion/removal/reorder upstream.
  /// Restores the same id when it survived; otherwise lands on the nearest
  /// surviving neighbor by the OLD index (never the new list's index of a
  /// now-gone id), falling back to the first item.
  void updateItems(List<String> newItemIds) {
    final oldId = _selectedId;
    final oldIndex = selectedIndex;
    _itemIds = List<String>.of(newItemIds);
    if (_itemIds.isEmpty) {
      _selectedId = null;
      return;
    }
    if (oldId != null && _itemIds.contains(oldId)) {
      _selectedId = oldId;
      return;
    }
    if (oldIndex == null) {
      _selectedId = _itemIds.first;
      return;
    }
    final clamped = oldIndex.clamp(0, _itemIds.length - 1);
    _selectedId = _itemIds[clamped];
  }

  /// The scroll offset that lands the row on the selected item, moving in
  /// exact multiples of [itemPitch] (poster/tile width + its gap) rather
  /// than a free-scrolling geometric offset — see phase step 6, "TV
  /// movement scrolls exactly one item pitch".
  double targetScrollOffset(double itemPitch) {
    final index = selectedIndex;
    return index == null ? 0 : index * itemPitch;
  }
}
