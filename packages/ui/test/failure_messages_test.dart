import 'package:ui/src/l10n_gen/app_strings_en.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

final class _UnknownFailure extends AppFailure {
  const _UnknownFailure()
    : super(code: 'future.failure.code', message: 'future failure');
}

void main() {
  test('every registered contract code has a distinct specific message', () {
    final failures = <AppFailure>[
      for (final code in knownFailureCodes) _CodeFailure(code),
    ];
    final messages = failures
        .map((failure) => messageForFailure(failure, strings: AppStringsEn()))
        .toList();
    // Local transport failures are part of the composed error surface too.
    expect(failures, hasLength(28));
    expect(messages.toSet(), hasLength(messages.length));
    expect(messages, everyElement(isNot(contains('Something went wrong'))));
  });

  test('unknown codes retain the raw code and invoke the warning hook', () {
    String? warned;
    final message = messageForFailure(
      const _UnknownFailure(),
      strings: AppStringsEn(),
      onUnknown: (code, _) => warned = code,
    );
    expect(message, contains('future.failure.code'));
    expect(warned, 'future.failure.code');
  });
}

final class _CodeFailure extends AppFailure {
  _CodeFailure(String code) : super(code: code, message: code);
}
