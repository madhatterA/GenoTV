import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class LtFileInfo extends Struct {
  @Int64()
  external int offset;
  @Int64()
  external int size;
  @Int32()
  external int pathLength;
  @Int32()
  external int isPad;
}

final class LtAlert extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int piece;
  @Int32()
  external int peers;
  @Int32()
  external int errorCode;
  @Int32()
  external int messageLength;
  @UintPtr()
  external int torrent;
}

typedef _CreateNative = Pointer<Void> Function();
typedef LtCreate = Pointer<Void> Function();
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef LtDestroy = void Function(Pointer<Void>);
typedef _ErrorNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef LtError = int Function(Pointer<Void>, Pointer<Utf8>, int);

/// The complete C ABI function table. C++ types never cross this boundary.
final class LtBindings {
  LtBindings(DynamicLibrary library)
    : create = library.lookupFunction<_CreateNative, LtCreate>(
        'transport_lt_session_create',
      ),
      destroy = library.lookupFunction<_DestroyNative, LtDestroy>(
        'transport_lt_session_destroy',
      ),
      lastError = library.lookupFunction<_ErrorNative, LtError>(
        'transport_lt_session_last_error',
      ),
      addMagnet = _addMagnet(library),
      addTorrent = _addTorrent(library),
      loadResume = _loadResume(library),
      removeTorrent = _removeTorrent(library),
      closeTorrent = _closeTorrent(library),
      closeComplete = _closeComplete(library),
      metadataReady = _metadataReady(library),
      fileCount = _fileCount(library),
      pieceLength = _pieceLength(library),
      pieceCount = _pieceCount(library),
      infoHash = _infoHash(library),
      fileInfo = _fileInfo(library),
      pieceAvailable = _pieceAvailable(library),
      copyBitfield = _copyBitfield(library),
      read = _read(library),
      prioritizeFiles = _prioritizeFiles(library),
      filePriority = _filePriority(library),
      setPiecePriority = _setPiecePriority(library),
      setPieceDeadline = _setPieceDeadline(library),
      clearPieceDeadlines = _clearPieceDeadlines(library),
      status = _status(library),
      _library = library,
      popAlerts = _popAlerts(library),
      saveResume = _saveResume(library),
      loadTorrentResume = _loadTorrentResume(library),
      evictPieces = _evictPieces(library),
      sessionSet = library.lookupFunction<LtSetNative, LtSet>(
        'transport_lt_session_set',
      ),
      sessionGet = library.lookupFunction<LtGetNative, LtGet>(
        'transport_lt_session_get',
      ),
      torrentSet = library.lookupFunction<LtSetNative, LtSet>(
        'transport_lt_torrent_set',
      ),
      torrentGet = library.lookupFunction<LtGetNative, LtGet>(
        'transport_lt_torrent_get',
      ),
      initializeDownload = library
          .lookupFunction<InitializeDownloadNative, InitializeDownload>(
            'transport_lt_torrent_initialize_download',
          );

  final LtCreate create;
  final LtDestroy destroy;
  final LtError lastError;
  final AddMagnet addMagnet;
  final AddTorrent addTorrent;
  final LoadResume loadResume;
  final RemoveTorrent removeTorrent;
  final CloseTorrent closeTorrent;
  final CloseComplete closeComplete;
  final MetadataReady metadataReady;
  final FileCount fileCount;
  final PieceLength pieceLength;
  final PieceCount pieceCount;
  final InfoHash infoHash;
  final FileInfo fileInfo;
  final PieceAvailable pieceAvailable;
  final CopyBitfield copyBitfield;
  final ReadTorrent read;
  final PrioritizeFiles prioritizeFiles;
  final FilePriority filePriority;
  final SetPiecePriority setPiecePriority;
  final SetPieceDeadline setPieceDeadline;
  final ClearPieceDeadlines clearPieceDeadlines;
  final Status status;
  final DynamicLibrary _library;

  /// Bound on first use, so a shim without the stats call can never keep a
  /// torrent from starting; only reading the stats fails.
  late final StatsFn stats = _stats(_library);
  final PopAlerts popAlerts;
  final SaveResume saveResume;
  final LoadTorrentResume loadTorrentResume;
  final EvictPieces evictPieces;
  final InitializeDownload initializeDownload;
  final LtSet sessionSet;
  final LtGet sessionGet;
  final LtSet torrentSet;
  final LtGet torrentGet;
}

typedef LtSetNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef LtSet = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef LtGetNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
);
typedef LtGet = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
);

typedef AddMagnetNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Int32,
);
typedef AddMagnet = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
  int,
);
typedef AddTorrentNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Int32,
);
typedef AddTorrent = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Utf8>,
  int,
  int,
);
typedef LoadResumeNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Int32,
);
typedef LoadResume = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Utf8>,
  int,
  int,
);
typedef RemoveTorrentNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Int32,
);
typedef RemoveTorrent = int Function(Pointer<Void>, Pointer<Void>, int);
typedef CloseTorrentNative = Void Function(Pointer<Void>);
typedef CloseTorrent = void Function(Pointer<Void>);
typedef CloseCompleteNative = Int32 Function(Pointer<Void>);
typedef CloseComplete = int Function(Pointer<Void>);
typedef MetadataReadyNative = Int32 Function(Pointer<Void>);
typedef MetadataReady = int Function(Pointer<Void>);
typedef FileCountNative = Int32 Function(Pointer<Void>);
typedef FileCount = int Function(Pointer<Void>);
typedef PieceLengthNative = Int32 Function(Pointer<Void>);
typedef PieceLength = int Function(Pointer<Void>);
typedef PieceCountNative = Int32 Function(Pointer<Void>);
typedef PieceCount = int Function(Pointer<Void>);

typedef InfoHashNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef InfoHash = int Function(Pointer<Void>, Pointer<Utf8>, int);
InfoHash _infoHash(DynamicLibrary l) => l
    .lookupFunction<InfoHashNative, InfoHash>('transport_lt_torrent_info_hash');
typedef FileInfoNative = Int32 Function(
  Pointer<Void>,
  Int32,
  Pointer<LtFileInfo>,
  Pointer<Utf8>,
  Int32,
);
typedef FileInfo = int Function(
  Pointer<Void>,
  int,
  Pointer<LtFileInfo>,
  Pointer<Utf8>,
  int,
);
typedef PieceAvailableNative = Int32 Function(Pointer<Void>, Int32);
typedef PieceAvailable = int Function(Pointer<Void>, int);
typedef CopyBitfieldNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
);
typedef CopyBitfield = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef ReadNative = Int32 Function(
  Pointer<Void>,
  Int32,
  Int64,
  Pointer<Uint8>,
  Int32,
);
typedef ReadTorrent = int Function(
  Pointer<Void>,
  int,
  int,
  Pointer<Uint8>,
  int,
);
typedef PrioritizeFilesNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
);
typedef PrioritizeFiles = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef FilePriorityNative = Int32 Function(Pointer<Void>, Int32);
typedef FilePriority = int Function(Pointer<Void>, int);
typedef SetPiecePriorityNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef SetPiecePriority = int Function(Pointer<Void>, int, int);
typedef SetPieceDeadlineNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef SetPieceDeadline = int Function(Pointer<Void>, int, int);
typedef ClearPieceDeadlinesNative = Int32 Function(Pointer<Void>);
typedef ClearPieceDeadlines = int Function(Pointer<Void>);

/// `transport_lt_stats` in lt_shim.h (libtorrent torrent_status counters).
final class LtStatsStruct extends Struct {
  @Int64()
  external int totalUpload;
  @Float()
  external double distributedCopies;
  @Int32()
  external int uploadRate;
  @Int32()
  external int numSeeds;
  @Int32()
  external int numPeers;
  @Int32()
  external int numComplete;
  @Int32()
  external int numIncomplete;
  @Int32()
  external int numPieces;
}

typedef StatsNative = Int32 Function(Pointer<Void>, Pointer<LtStatsStruct>);
typedef StatsFn = int Function(Pointer<Void>, Pointer<LtStatsStruct>);

typedef StatusNative = Int32 Function(
  Pointer<Void>,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int64>,
  Pointer<Int64>,
  Pointer<Int32>,
);
typedef Status = int Function(
  Pointer<Void>,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int64>,
  Pointer<Int64>,
  Pointer<Int32>,
);
typedef PopAlertsNative = Int32 Function(
  Pointer<Void>,
  Pointer<LtAlert>,
  Int32,
  Pointer<Utf8>,
  Int32,
);
typedef PopAlerts = int Function(
  Pointer<Void>,
  Pointer<LtAlert>,
  int,
  Pointer<Utf8>,
  int,
);
typedef SaveResumeNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef SaveResume = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef LoadTorrentResumeNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
);
typedef LoadTorrentResume = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Uint8>,
  int,
);
typedef EvictPiecesNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Int32>,
  Int32,
);
typedef EvictPieces = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Int32>,
  int,
);

typedef InitializeDownloadNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Int32,
  Int32,
  Int32,
);
typedef InitializeDownload = int Function(
  Pointer<Void>,
  Pointer<Void>,
  int,
  int,
  int,
);

AddMagnet _addMagnet(DynamicLibrary l) =>
    l.lookupFunction<AddMagnetNative, AddMagnet>('transport_lt_add_magnet');
AddTorrent _addTorrent(DynamicLibrary l) =>
    l.lookupFunction<AddTorrentNative, AddTorrent>('transport_lt_add_torrent');
LoadResume _loadResume(DynamicLibrary l) =>
    l.lookupFunction<LoadResumeNative, LoadResume>('transport_lt_load_resume');
RemoveTorrent _removeTorrent(DynamicLibrary l) =>
    l.lookupFunction<RemoveTorrentNative, RemoveTorrent>(
      'transport_lt_torrent_remove',
    );
CloseTorrent _closeTorrent(DynamicLibrary l) =>
    l.lookupFunction<CloseTorrentNative, CloseTorrent>(
      'transport_lt_torrent_close',
    );
CloseComplete _closeComplete(DynamicLibrary l) =>
    l.lookupFunction<CloseCompleteNative, CloseComplete>(
      'transport_lt_torrent_close_complete',
    );
MetadataReady _metadataReady(DynamicLibrary l) =>
    l.lookupFunction<MetadataReadyNative, MetadataReady>(
      'transport_lt_torrent_metadata_ready',
    );
FileCount _fileCount(DynamicLibrary l) =>
    l.lookupFunction<FileCountNative, FileCount>(
      'transport_lt_torrent_file_count',
    );
PieceLength _pieceLength(DynamicLibrary l) =>
    l.lookupFunction<PieceLengthNative, PieceLength>(
      'transport_lt_torrent_piece_length',
    );
PieceCount _pieceCount(DynamicLibrary l) =>
    l.lookupFunction<PieceCountNative, PieceCount>(
      'transport_lt_torrent_piece_count',
    );
FileInfo _fileInfo(DynamicLibrary l) => l
    .lookupFunction<FileInfoNative, FileInfo>('transport_lt_torrent_file_info');
PieceAvailable _pieceAvailable(DynamicLibrary l) =>
    l.lookupFunction<PieceAvailableNative, PieceAvailable>(
      'transport_lt_torrent_piece_available',
    );
CopyBitfield _copyBitfield(DynamicLibrary l) =>
    l.lookupFunction<CopyBitfieldNative, CopyBitfield>(
      'transport_lt_torrent_copy_piece_bitfield',
    );
ReadTorrent _read(DynamicLibrary l) =>
    l.lookupFunction<ReadNative, ReadTorrent>('transport_lt_torrent_read');
PrioritizeFiles _prioritizeFiles(DynamicLibrary l) =>
    l.lookupFunction<PrioritizeFilesNative, PrioritizeFiles>(
      'transport_lt_torrent_prioritize_files',
    );
FilePriority _filePriority(DynamicLibrary l) =>
    l.lookupFunction<FilePriorityNative, FilePriority>(
      'transport_lt_torrent_file_priority',
    );
SetPiecePriority _setPiecePriority(DynamicLibrary l) =>
    l.lookupFunction<SetPiecePriorityNative, SetPiecePriority>(
      'transport_lt_torrent_set_piece_priority',
    );
SetPieceDeadline _setPieceDeadline(DynamicLibrary l) =>
    l.lookupFunction<SetPieceDeadlineNative, SetPieceDeadline>(
      'transport_lt_torrent_set_piece_deadline',
    );
ClearPieceDeadlines _clearPieceDeadlines(DynamicLibrary l) =>
    l.lookupFunction<ClearPieceDeadlinesNative, ClearPieceDeadlines>(
      'transport_lt_torrent_clear_piece_deadlines',
    );
StatsFn _stats(DynamicLibrary l) =>
    l.lookupFunction<StatsNative, StatsFn>('transport_lt_torrent_stats');
Status _status(DynamicLibrary l) =>
    l.lookupFunction<StatusNative, Status>('transport_lt_torrent_status');
PopAlerts _popAlerts(DynamicLibrary l) =>
    l.lookupFunction<PopAlertsNative, PopAlerts>('transport_lt_pop_alerts');
SaveResume _saveResume(DynamicLibrary l) =>
    l.lookupFunction<SaveResumeNative, SaveResume>(
      'transport_lt_torrent_save_resume',
    );
LoadTorrentResume _loadTorrentResume(DynamicLibrary l) =>
    l.lookupFunction<LoadTorrentResumeNative, LoadTorrentResume>(
      'transport_lt_torrent_load_resume',
    );
EvictPieces _evictPieces(DynamicLibrary l) =>
    l.lookupFunction<EvictPiecesNative, EvictPieces>(
      'transport_lt_torrent_evict_pieces',
    );
