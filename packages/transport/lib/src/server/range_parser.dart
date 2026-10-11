import 'package:contracts/contracts.dart';

enum RangeParseKind { absent, invalid, valid, unsatisfiable }

class ParsedRange {
  const ParsedRange._(this.kind, this.range);
  const ParsedRange.absent() : this._(RangeParseKind.absent, null);
  const ParsedRange.invalid() : this._(RangeParseKind.invalid, null);
  const ParsedRange.unsatisfiable()
    : this._(RangeParseKind.unsatisfiable, null);
  const ParsedRange.valid(ByteRange range)
    : this._(RangeParseKind.valid, range);

  final RangeParseKind kind;
  final ByteRange? range;
}

/// Parses one RFC 9110 byte range. Multipart ranges are intentionally rejected.
ParsedRange parseRange(String? header, int size) {
  if (header == null) return const ParsedRange.absent();
  if (!header.trimLeft().startsWith('bytes=')) {
    return const ParsedRange.invalid();
  }
  final value = header.trimLeft().substring(6).trim();
  // The frozen server policy rejects multipart requests rather than serving
  // only the first part.
  if (value.isEmpty) return const ParsedRange.invalid();
  if (value.contains(',')) return const ParsedRange.unsatisfiable();
  final dash = value.indexOf('-');
  if (dash < 0 || value.indexOf('-', dash + 1) >= 0) {
    return const ParsedRange.invalid();
  }
  final first = value.substring(0, dash).trim();
  final second = value.substring(dash + 1).trim();
  final start = int.tryParse(first);
  final end = int.tryParse(second);
  if (first.isEmpty) {
    if (end == null) return const ParsedRange.invalid();
    if (end <= 0 || size <= 0) return const ParsedRange.unsatisfiable();
    final length = end > size ? size : end;
    return ParsedRange.valid(ByteRange(size - length, size - 1));
  }
  if (start == null || start < 0 || size <= 0 || start >= size) {
    return const ParsedRange.unsatisfiable();
  }
  final finalByte = end == null || end >= size ? size - 1 : end;
  if (finalByte < start) return const ParsedRange.unsatisfiable();
  return ParsedRange.valid(ByteRange(start, finalByte));
}
