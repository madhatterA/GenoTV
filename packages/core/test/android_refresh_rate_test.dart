import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'display accepts OS rates and rejects nonpositive or nonfinite rates',
    () async {
      final values = SettingsValues(MemorySettingsStore());
      addTearDown(values.dispose);
      final def = settingById('display.refreshRate');
      for (final rate in ['auto', '90.0', '59.999996185302734', '120.125']) {
        await values.write(def, rate);
        expect(values.read<String>(def), rate);
      }
      for (final invalid in ['', 'NaN', 'Infinity', '-1', '0', 'Auto', 'abc']) {
        expect(() => values.write(def, invalid), throwsArgumentError);
      }
    },
  );
}
