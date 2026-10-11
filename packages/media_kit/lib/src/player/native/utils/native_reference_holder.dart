/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:safe_local_storage/safe_local_storage.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import 'package:media_kit/ffi/src/allocation.dart';
import 'package:media_kit/src/player/native/utils/temp_file.dart';
import 'package:media_kit/src/values.dart';

/// Callback invoked to notify about the released references.
typedef NativeReferenceHolderCallback = void Function(List<Pointer<Void>>);

/// {@template native_reference_holder}
///
/// NativeReferenceHolder
/// ---------------------
/// Holds references to [Pointer<generated.mpv_handle>]s created during the application runtime, while running in debug mode.
/// These references can be used to dispose the [Pointer<generated.mpv_handle>]s when they are no longer needed i.e. upon hot-restart.
///
/// {@endtemplate}
class NativeReferenceHolder {
  /// Maximum number of references that can be held.
  static const int kReferenceBufferSize = 512;

  /// Singleton instance.
  static final NativeReferenceHolder instance = NativeReferenceHolder._();

  /// Whether the [instance] is initialized.
  static bool initialized = false;

  /// {@macro native_reference_holder}
  NativeReferenceHolder._();

  /// Initializes the instance.
  static void ensureInitialized(NativeReferenceHolderCallback callback) {
    if (!kDebugMode) return;
    if (initialized) return;
    initialized = true;
    instance._ensureInitialized(callback);
  }

  void _ensureInitialized(NativeReferenceHolderCallback callback) async {
    // PIDs and service ports can be reused; VM birth time survives hot-restart.
    // Without a service, never recover pointers from disk.
    final serviceUri = (await Service.getInfo()).serverUri;
    var identity = Uuid().v4();
    int? startTime;
    if (serviceUri != null) {
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        const deadline = Duration(seconds: 5);
        final request =
            await client.getUrl(serviceUri.resolve('getVM')).timeout(deadline);
        final response = await request.close().timeout(deadline);
        final body = await utf8.decoder.bind(response).join().timeout(deadline);
        final vm = (jsonDecode(body) as Map<String, dynamic>)['result']
            as Map<String, dynamic>;
        if (response.statusCode != HttpStatus.ok ||
            vm['pid'] != pid ||
            vm['startTime'] is! int) {
          throw StateError(
            'Cannot identify current VM for native reference recovery',
          );
        }
        // The VM recomputes startTime on every getVM call, so it jitters by
        // a few ms between calls/isolates: store it and compare with tolerance.
        startTime = vm['startTime'] as int;
        identity = 'vm';
      } catch (error) {
        stderr.writeln(
            '$kTag VM identity unavailable; using fresh buffer: $error');
      } finally {
        client.close(force: true);
      }
    }
    _file = File(
      path.join(
        TempFile.directory,
        'com.alexmercerind.media_kit.NativeReferenceHolder.$pid.$identity',
      ),
    );
    int? located;
    if (await _file.exists_()) {
      // File content: "<address>" (no VM identity) or "<startTime> <address>".
      final parts = ((await _file.readAsString_()) ?? '').trim().split(' ');
      final address = int.tryParse(parts.last);
      final stored = parts.length == 2 ? int.tryParse(parts.first) : null;
      if (address != null &&
          (startTime == null
              ? parts.length == 1
              : stored != null && (stored - startTime).abs() <= 1000)) {
        located = address;
      }
    }
    if (located == null) {
      // Allocate reference buffer.
      _referenceBuffer = calloc<IntPtr>(kReferenceBufferSize);
      final address = _referenceBuffer.address;
      await _file.write_(
          startTime == null ? '$address' : '$startTime $address');
      print('$kTag Allocated $address');
    } else {
      // Locate reference buffer.
      _referenceBuffer = Pointer<IntPtr>.fromAddress(located);
      print('$kTag Located $located');
    }

    final references = <Pointer<Void>>[];

    for (int i = 0; i < kReferenceBufferSize; i++) {
      final referencePtr = _referenceBuffer + i;
      final referenceAddress = referencePtr.value;
      referencePtr.value = 0;
      if (referenceAddress != 0) {
        references.add(Pointer.fromAddress(referenceAddress));
      }
    }

    callback(references);

    _completer.complete();
  }

  /// Saves the reference.
  Future<void> add(Pointer reference) async {
    if (!initialized) return;
    if (reference == nullptr) return;
    await _completer.future;
    return _lock.synchronized(() async {
      for (int i = 0; i < kReferenceBufferSize; i++) {
        final referenceValue = _referenceBuffer + i;
        final referencePtr = Pointer.fromAddress(referenceValue.value);
        // NOTE: Do not compare .value with .address. Bad things may happen on 32-bit systems.
        if (referencePtr.address == 0) {
          referenceValue.value = reference.address;
          break;
        }
      }
    });
  }

  /// Removes the reference.
  Future<void> remove(Pointer reference) async {
    if (!initialized) return;
    if (reference == nullptr) return;
    await _completer.future;
    return _lock.synchronized(() async {
      for (int i = 0; i < kReferenceBufferSize; i++) {
        final referenceValue = _referenceBuffer + i;
        final referencePtr = Pointer.fromAddress(referenceValue.value);
        // NOTE: Do not compare .value with .address. Bad things may happen on 32-bit systems.
        if (referencePtr.address == reference.address) {
          referenceValue.value = 0;
          break;
        }
      }
    });
  }

  /// [Lock] used to synchronize access to the reference buffer.
  final Lock _lock = Lock();

  /// [Completer] used to wait for the reference buffer to be allocated.
  final Completer<void> _completer = Completer<void>();

  /// [File] used to store [int] address to the reference buffer.
  /// This is necessary to have a persistent to the reference buffer across hot-restarts.
  late final File _file;

  /// [Pointer] to the reference buffer.
  late final Pointer<IntPtr> _referenceBuffer;

  static const String kTag = 'media_kit: NativeReferenceHolder:';
}
