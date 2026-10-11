/// Provided by `packages/persistence` (Part 01).
abstract interface class FavouritesRepository {
  Future<bool> isFavourite(String mediaId);
  Future<void> setFavourite(String mediaId, bool value);
  Future<List<String>> all();
  Stream<List<String>> watchAll();
}
