import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';

final class _DisplayChannel implements PlatformChannel {
  Object? response = const {
    'supported': true,
    'choices': {'': 'Default', 'Touchscreen': 'Touchscreen'},
    'selected': 'Touchscreen',
  };
  PlatformException? failure;
  String? method;
  Object? arguments;
  final _events = StreamController<Object?>.broadcast();

  void emit(Object event) => _events.add(event);

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    this.method = method;
    this.arguments = arguments;
    if (failure case final error?) throw error;
    return response;
  }

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  late _DisplayChannel channel;
  late DisplayScreenService service;

  setUp(() {
    channel = _DisplayChannel();
    service = DisplayScreenService(channel: channel);
  });
  tearDown(() => channel.dispose());

  test('enumerates Kodi iOS Default and Touchscreen choices', () async {
    final screens = await service.displays();
    expect(channel.method, 'display.screens');
    expect(channel.arguments, isNull);
    expect(screens.choices, {'': 'Default', 'Touchscreen': 'Touchscreen'});
    expect(screens.selected, 'Touchscreen');
  });

  test('selects the native screen and returns its current selection', () async {
    channel.response = const {
      'supported': true,
      'choices': {
        '': 'Default',
        'Touchscreen': 'Touchscreen',
        'External': 'External',
      },
      'selected': 'External',
    };
    final screens = await service.select('External');
    expect(channel.method, 'display.select');
    expect(channel.arguments, {'id': 'External'});
    expect(screens.choices['External'], 'External');
    expect(screens.selected, 'External');
  });

  test('disconnect event publishes native Touchscreen fallback', () async {
    final next = service.changes.first;
    channel.emit({'event': 'audioRouteChanged'});
    channel.emit({
      'event': 'displayScreensChanged',
      'choices': {'': 'Default', 'Touchscreen': 'Touchscreen'},
      'selected': 'Touchscreen',
    });
    final screens = await next;
    expect(screens.choices, {'': 'Default', 'Touchscreen': 'Touchscreen'});
    expect(screens.selected, 'Touchscreen');
  });

  test('native errors propagate from enumeration and selection', () async {
    final failure = PlatformException(
      code: 'display.unavailable',
      message: 'The external screen disconnected',
    );
    channel.failure = failure;
    await expectLater(service.displays(), throwsA(same(failure)));
    await expectLater(service.select('External'), throwsA(same(failure)));
  });
}
