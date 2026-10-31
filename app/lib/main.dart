import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';
import 'package:platform_services/platform_services.dart';

import 'crash_capture.dart';

import 'composition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installNetworkPolicy();
  CrashCapture? capture;
  final nativeCrash = NativeCrashCapture();
  try {
    final logger = ConsoleLogger();
    final support = await AppPaths(logger: logger).support;
    final crashLog = CrashLog(
      Directory('${support.path}${Platform.pathSeparator}crashes'),
    );
    capture = CrashCapture(crashLog, logger)..install();
    await nativeCrash.install(crashLog.nativePendingPath);
    final composition = await AppComposition.create(crashLog: crashLog);
    composition.startAfterFirstFrame();
    runApp(_ComposedApp(composition, capture, nativeCrash));
  } catch (error, stack) {
    capture?.capture('startup', error, stack);
    runApp(
      MaterialApp(
        onGenerateTitle: (context) => AppStrings.of(context).app_title,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: AppStrings.localizationsDelegates,
        theme: AppTheme.dark(tv: false),
        home: ErrorView(
          failure: UnexpectedFailure(cause: error, stack: stack),
          fullScreen: true,
        ),
      ),
    );
  }
}

final class _ComposedApp extends StatefulWidget {
  const _ComposedApp(this.composition, this.capture, this.nativeCrash);

  final AppComposition composition;
  final CrashCapture capture;
  final NativeCrashCapture nativeCrash;

  @override
  State<_ComposedApp> createState() => _ComposedAppState();
}

final class _ComposedAppState extends State<_ComposedApp> {
  @override
  Widget build(BuildContext context) => widget.composition.buildApp();

  @override
  void dispose() {
    widget.capture.dispose();
    unawaited(widget.nativeCrash.uninstall());
    unawaited(widget.composition.dispose());
    super.dispose();
  }
}

/// Retained as the lightweight foundation smoke-test surface; production
/// startup above uses the real composition root.
class BootApp extends StatelessWidget {
  const BootApp({super.key});

  static const String appName = 'GenoTV';

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppStrings.of(context).app_title,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: AppStrings.localizationsDelegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const BootScreen(),
  );
}

class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final paths = AppPaths(logger: ConsoleLogger());
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppText(
              AppStrings.of(context).app_title,
              style: textTheme.headlineMedium,
            ),
            AppText.content(
              Platform.operatingSystem,
              key: const Key('boot-platform'),
            ),
            FutureBuilder<Directory>(
              future: paths.cache,
              builder: (context, snapshot) => AppText.content(
                snapshot.hasData
                    ? snapshot.data!.path
                    : AppStrings.of(context).app_resolvingCache,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
