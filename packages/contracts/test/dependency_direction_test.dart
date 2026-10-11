import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one architectural rule that makes parallel Part execution safe:
/// dependencies point one way only, and `contracts` stays free of storage
/// dependencies. See `planning/README.md` and `planning/CONTRACTS.md`.
///
/// This test reads pubspecs as text on purpose. A YAML parser would be a
/// dependency added to catch four substrings.
void main() {
  /// Packages that implement behaviour. None of them may depend on another.
  const implementationPackages = <String>{
    'playback',
    'transport',
    'ui',
    'platform_services',
    'persistence',
    'content_sources',
  };

  /// Dependencies that must never reach `contracts`; a storage dependency there
  /// would be inherited by every package in the workspace.
  const forbiddenInContracts = <String>['drift', 'sqlite3'];

  late Directory packagesDir;

  setUpAll(() {
    var dir = Directory.current;
    while (!Directory('${dir.path}/packages').existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        fail('Could not locate the repository root from ${Directory.current}');
      }
      dir = parent;
    }
    packagesDir = Directory('${dir.path}/packages');
  });

  /// The dependency names declared under `dependencies:` — not dev_dependencies,
  /// which may legitimately reference anything for testing.
  Set<String> declaredDependencies(String pubspec) {
    final lines = pubspec.split('\n');
    final start = lines.indexWhere((l) => l.trimRight() == 'dependencies:');
    if (start == -1) return <String>{};
    final names = <String>{};
    for (final line in lines.skip(start + 1)) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      // A new top-level key ends the dependencies block.
      if (!line.startsWith(' ')) break;
      final match = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
      if (match != null) names.add(match.group(1)!);
    }
    return names;
  }

  Map<String, Set<String>> readAll() {
    final result = <String, Set<String>>{};
    for (final entity in packagesDir.listSync().whereType<Directory>()) {
      final pubspec = File('${entity.path}/pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      result[entity.path.split(Platform.pathSeparator).last] =
          declaredDependencies(pubspec.readAsStringSync());
    }
    return result;
  }

  test('every package declares a pubspec', () {
    final all = readAll();
    expect(all.keys, containsAll(implementationPackages));
    expect(all.keys, containsAll(<String>['core', 'contracts']));
  });

  test('no implementation package depends on another implementation package', () {
    final all = readAll();
    for (final name in implementationPackages) {
      final deps = all[name];
      expect(deps, isNotNull, reason: 'missing package: $name');
      final violations = deps!.intersection(implementationPackages)
        ..remove(name);
      expect(
        violations,
        isEmpty,
        reason: '$name must not depend on ${violations.join(', ')}. '
            'Cross-Part calls go through packages/contracts only.',
      );
    }
  });

  test('contracts depends only on core, flutter and flutter_test', () {
    final deps = readAll()['contracts']!;
    // flutter_test is legitimate here (not a violation of "pure interface
    // package"): lib/testing/ is shipped code other packages' tests import,
    // so it must be a regular dependency (Chapter 03 Phase 06).
    expect(
      deps.difference(<String>{'core', 'flutter', 'flutter_test'}),
      isEmpty,
      reason: 'contracts must stay a pure interface package',
    );
  });

  test('contracts has no storage dependency', () {
    final pubspec =
        File('${packagesDir.path}/contracts/pubspec.yaml').readAsStringSync();
    for (final forbidden in forbiddenInContracts) {
      expect(
        pubspec.contains(forbidden),
        isFalse,
        reason: 'contracts must not reference $forbidden (planning/README.md, D5)',
      );
    }
  });

  test('core is a leaf: it depends on no workspace package', () {
    final deps = readAll()['core']!;
    final workspacePackages = {...implementationPackages, 'contracts'};
    expect(
      deps.intersection(workspacePackages),
      isEmpty,
      reason: 'core is the bottom of the dependency graph',
    );
  });

  test('persistence is the only package that may depend on drift', () {
    for (final entity in packagesDir.listSync().whereType<Directory>()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name == 'persistence') continue;
      final pubspec = File('${entity.path}/pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      expect(
        declaredDependencies(pubspec.readAsStringSync()).contains('drift'),
        isFalse,
        reason: '$name must not depend on drift',
      );
    }
  });
}
