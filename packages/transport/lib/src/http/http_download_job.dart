import 'package:contracts/contracts.dart';

import 'aria2_backend.dart';
import 'range_support_probe.dart';

class HttpDownloadJob {
  HttpDownloadJob({
    required this.backend,
    required this.spec,
    required this.outPath,
    RangeSupportProbe? probe,
  }) : _probe = probe ?? RangeSupportProbe();
  final Aria2Backend backend;
  final SourceSpec spec;
  final String outPath;
  final RangeSupportProbe _probe;
  String? jobId;

  Future<String> start() async {
    final result = await _probe.probe(spec);
    if (!result.supported) {
      throw const TransportFailure.httpNoRangeSupport(
        cause: 'server does not support ranges',
      );
    }
    jobId = await backend.addDownload(spec, outPath);
    return jobId!;
  }
}
