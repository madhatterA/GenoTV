import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'dart:developer';
import 'dart:isolate';

import 'package:media_kit/src/player/native/utils/native_reference_holder.dart';
import 'package:media_kit/src/player/native/utils/temp_file.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--service')) {
    await Service.controlWebServer(enable: false, silenceOutput: true);
    final service = await Service.controlWebServer(
      enable: true,
      silenceOutput: true,
    );
    if (service.serverUri == null) {
      throw StateError('VM service failed to start');
    }
  }
  // Simulate a reused PID holding an address from a dead process.
  final stale = File(
    '${TempFile.directory}/com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
  );
  await stale.writeAsString('1');
  final ready = Completer<void>();
  NativeReferenceHolder.ensureInitialized((references) {
    if (references.isNotEmpty) throw StateError('Stale references recovered');
    ready.complete();
  });
  await ready.future.timeout(const Duration(seconds: 10));
  await NativeReferenceHolder.instance.add(Pointer<Void>.fromAddress(42));
  await Isolate.run(recoverReferences);
  await NativeReferenceHolder.instance.remove(Pointer<Void>.fromAddress(42));
  stdout.writeln('legacy stale pointer ignored; same-VM recovery checked');
}

Future<void> recoverReferences() async {
  final hasService = (await Service.getInfo()).serverUri != null;
  final recovered = Completer<void>();
  NativeReferenceHolder.ensureInitialized((references) {
    if (hasService
        ? references.length != 1 || references.single.address != 42
        : references.isNotEmpty) {
      throw StateError('Incorrect same-VM reference recovery: $references');
    }
    recovered.complete();
  });
  await recovered.future.timeout(const Duration(seconds: 10));
}
