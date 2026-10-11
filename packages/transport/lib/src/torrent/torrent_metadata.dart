class TorrentFile {
  const TorrentFile({
    required this.path,
    required this.offset,
    required this.length,
  });
  final String path;
  final int offset;
  final int length;
}

class TorrentMetadata {
  const TorrentMetadata({required this.files, required this.pieceLength});
  final List<TorrentFile> files;
  final int pieceLength;
}
