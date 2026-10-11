// All live-network tests run here, one after another in one isolate. As
// separate *_test.dart files `flutter test` ran them in parallel processes and
// they starved each other against the same slow sites (bug_history.md,
// "live tests time out together"). The individual files are libraries without
// the _test suffix so they are not also collected on their own.
import 'live/digimoviez_live.dart' as digimoviez;
import 'live/knaben_live.dart' as knaben;
import 'live/thirtynama_live.dart' as thirtynama;
import 'live/tmdb_catalogue_live.dart' as tmdb_catalogue;
import 'live/tmdb_client_live.dart' as tmdb_client;
import 'live/torrent_galaxy_live.dart' as torrent_galaxy;
import 'live/torrent_search_live.dart' as torrent_search;

void main() {
  digimoviez.main();
  knaben.main();
  thirtynama.main();
  tmdb_catalogue.main();
  tmdb_client.main();
  torrent_galaxy.main();
  torrent_search.main();
}
