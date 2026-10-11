import 'package:contracts/contracts.dart';

void validateHttpValidator(String? expected, String? actual) {
  if (expected != null && actual != null && expected != actual) {
    throw TransportFailure.httpValidatorChanged(
      cause: 'expected $expected, received $actual',
    );
  }
}
