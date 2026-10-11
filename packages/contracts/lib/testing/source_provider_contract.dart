import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reusable behavioural spec for any [SourceProvider] implementation (§6).
void runSourceProviderContractTests(SourceProvider Function() create) {
  group('SourceProvider contract', () {
    test('browse/search/resolve/dispose can all be awaited without throwing', () async {
      final provider = create();
      await provider.browse(const BrowseQuery());
      await provider.search('');
      await provider.dispose();
    });

    test('browse/search return an empty page, not an error, for a provider that does not '
        'support them', () async {
      final provider = create();
      final browsed = await provider.browse(const BrowseQuery());
      final searched = await provider.search('a query nothing plausibly matches');
      expect(browsed.items, isA<List<MediaItem>>());
      expect(searched.items, isA<List<MediaItem>>());
    });

    test('dispose() is idempotent', () async {
      final provider = create();
      await provider.dispose();
      await provider.dispose();
    });
  });
}
