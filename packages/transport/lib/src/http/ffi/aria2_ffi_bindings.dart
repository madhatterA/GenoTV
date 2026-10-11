import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class Aria2DownloadStatus extends Struct {
  @Int32()
  external int state;
  @Int32()
  external int errorCode;
  @Int32()
  external int connections;
  @Int32()
  external int pieceLength;
  @Int32()
  external int pieceCount;
  @Int64()
  external int totalLength;
  @Int64()
  external int completedLength;
  @Int32()
  external int downloadRate;
  @Int32()
  external int bitfieldLength;
}

typedef Aria2CreateNative = Pointer<Void> Function();
typedef Aria2Create = Pointer<Void> Function();
typedef Aria2DestroyNative = Void Function(Pointer<Void>);
typedef Aria2Destroy = void Function(Pointer<Void>);
typedef Aria2LastErrorNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Int32,
);
typedef Aria2LastError = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef Aria2AddUriNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Uint64>,
);
typedef Aria2AddUri = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Uint64>,
);
typedef Aria2PollNative = Int32 Function(Pointer<Void>);
typedef Aria2Poll = int Function(Pointer<Void>);
typedef Aria2StatusNative = Int32 Function(
  Pointer<Void>,
  Uint64,
  Pointer<Aria2DownloadStatus>,
  Pointer<Uint8>,
  Int32,
);
typedef Aria2Status = int Function(
  Pointer<Void>,
  int,
  Pointer<Aria2DownloadStatus>,
  Pointer<Uint8>,
  int,
);
typedef Aria2ChangeOptionNative = Int32 Function(
  Pointer<Void>,
  Uint64,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
);
typedef Aria2ChangeOption = int Function(
  Pointer<Void>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
);
typedef Aria2GetOptionNative = Int32 Function(
  Pointer<Void>,
  Uint64,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
);
typedef Aria2GetOption = int Function(
  Pointer<Void>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
);
typedef Aria2RemoveNative = Int32 Function(Pointer<Void>, Uint64);
typedef Aria2Remove = int Function(Pointer<Void>, int);

typedef Aria2SetPausedNative = Int32 Function(Pointer<Void>, Uint64, Int32);
typedef Aria2SetPaused = int Function(Pointer<Void>, int, int);

/// ABI declarations shared by the iOS shim and its Dart owner.
final class Aria2FfiBindings {
  Aria2FfiBindings(DynamicLibrary library)
    : create = library.lookupFunction<Aria2CreateNative, Aria2Create>(
        'transport_aria2_create',
      ),
      destroy = library.lookupFunction<Aria2DestroyNative, Aria2Destroy>(
        'transport_aria2_destroy',
      ),
      destroyAddress = library.lookup<NativeFunction<Aria2DestroyNative>>(
        'transport_aria2_destroy',
      ),
      lastError = library.lookupFunction<Aria2LastErrorNative, Aria2LastError>(
        'transport_aria2_last_error',
      ),
      addUri = library.lookupFunction<Aria2AddUriNative, Aria2AddUri>(
        'transport_aria2_add_uri',
      ),
      poll = library.lookupFunction<Aria2PollNative, Aria2Poll>(
        'transport_aria2_poll',
      ),
      status = library.lookupFunction<Aria2StatusNative, Aria2Status>(
        'transport_aria2_status',
      ),
      changeOption = library
          .lookupFunction<Aria2ChangeOptionNative, Aria2ChangeOption>(
            'transport_aria2_change_option',
          ),
      getOption = library.lookupFunction<Aria2GetOptionNative, Aria2GetOption>(
        'transport_aria2_get_option',
      ),
      remove = library.lookupFunction<Aria2RemoveNative, Aria2Remove>(
        'transport_aria2_remove',
      ),
      setPaused = library.lookupFunction<Aria2SetPausedNative, Aria2SetPaused>(
        'transport_aria2_set_paused',
      );

  final Aria2Create create;
  final Aria2Destroy destroy;
  final Pointer<NativeFunction<Aria2DestroyNative>> destroyAddress;
  final Aria2LastError lastError;
  final Aria2AddUri addUri;
  final Aria2Poll poll;
  final Aria2Status status;
  final Aria2ChangeOption changeOption;
  final Aria2GetOption getOption;
  final Aria2Remove remove;
  final Aria2SetPaused setPaused;
}
