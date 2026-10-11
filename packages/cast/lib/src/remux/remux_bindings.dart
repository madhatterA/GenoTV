import 'dart:convert';
import 'dart:ffi';

typedef _ConfigureNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Int64,
);
typedef _Configure = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  int,
);

/// The C job owns copied configuration and all FFmpeg resources.
final class RemuxBindings {
  RemuxBindings(String path) : library = DynamicLibrary.open(path);
  final DynamicLibrary library;
  late final create = library
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'remux_create',
      );
  late final configure = library.lookupFunction<_ConfigureNative, _Configure>(
    'remux_configure',
  );
  late final keep = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('remux_keep');
  late final subtitle = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>),
        int Function(Pointer<Void>, Pointer<Uint8>)
      >('remux_subtitle');
  late final run = library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('remux_run');
  late final cancel = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('remux_cancel');
  late final destroy = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('remux_destroy');
  late final position = library
      .lookupFunction<
        Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('remux_position');
  late final duration = library
      .lookupFunction<
        Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('remux_duration');
  late final packets = library
      .lookupFunction<
        Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('remux_packets');
  late final liveJobs = library
      .lookupFunction<Int64 Function(), int Function()>('remux_live_jobs');
  late final _error = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('remux_error');
  late final _alloc = library
      .lookupFunction<
        Pointer<Void> Function(Int64),
        Pointer<Void> Function(int)
      >('remux_alloc');
  late final _free = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('remux_free');

  late final probe = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>),
        int Function(Pointer<Void>, Pointer<Uint8>)
      >('remux_probe');
  late final streamType = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Int32),
        Pointer<Uint8> Function(Pointer<Void>, int)
      >('remux_stream_type');
  late final streamCodec = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Int32),
        Pointer<Uint8> Function(Pointer<Void>, int)
      >('remux_stream_codec');

  late final streamAttachedPicture = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('remux_stream_attached_picture');

  String readString(Pointer<Uint8> pointer) {
    var length = 0;
    while (length < 511 && pointer[length] != 0) {
      length++;
    }
    return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
  }

  T withString<T>(String value, T Function(Pointer<Uint8>) action) {
    final bytes = utf8.encode(value);
    final pointer = _alloc(bytes.length + 1).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Remux string allocation failed');
    try {
      pointer.asTypedList(bytes.length + 1)
        ..setRange(0, bytes.length, bytes)
        ..[bytes.length] = 0;
      return action(pointer);
    } finally {
      _free(pointer.cast());
    }
  }

  String error(Pointer<Void> job) {
    final pointer = _error(job);
    var length = 0;
    while (length < 511 && pointer[length] != 0) {
      length++;
    }
    return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
  }
}
