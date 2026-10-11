import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import 'composition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final composition = await AppComposition.create();
    runApp(_ComposedApp(composition));
  } catch (error, stack) {
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
  const _ComposedApp(this.composition);

  final AppComposition composition;

  @override
  State<_ComposedApp> createState() => _ComposedAppState();
}

final class _ComposedAppState extends State<_ComposedApp> {
  @override
  Widget build(BuildContext context) => widget.composition.buildApp();

  @override
  void dispose() {
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
