import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

class _FocusGallery extends StatefulWidget {
  const _FocusGallery({required this.memory, this.onFocused});

  final FocusMemory memory;
  final ValueChanged<String>? onFocused;

  @override
  State<_FocusGallery> createState() => _FocusGalleryState();
}

class _FocusGalleryState extends State<_FocusGallery> {
  late final Map<String, FocusNode> nodes = <String, FocusNode>{
    for (final id in const <String>['a', 'b', 'c', 'd', 'disabled'])
      id: FocusNode(debugLabel: 'card-$id', skipTraversal: id == 'disabled'),
  };

  @override
  void dispose() {
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget card(String id, int order, {bool enabled = true}) =>
        FocusTraversalOrder(
          order: NumericFocusOrder(order.toDouble()),
          child: FocusableCard(
            key: ValueKey<String>('card-$id'),
            surfaceId: 'gallery',
            itemId: id,
            memory: widget.memory,
            focusNode: nodes[id],
            enabled: enabled,
            onFocused: () => widget.onFocused?.call(id),
            child: Text(id),
          ),
        );
    return FocusScaffold(
      child: Center(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DirectionalFocusGuide(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[card('a', 0), card('b', 1)],
                ),
              ),
              DirectionalFocusGuide(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[card('c', 2), card('d', 3)],
                ),
              ),
              card('disabled', 4, enabled: false),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: child,
);

void main() {
  testWidgets(
    'directional traversal skips disabled controls and preserves geometry',
    (tester) async {
      final memory = FocusMemory();
      final order = <String>[];
      await tester.pumpWidget(
        _app(_FocusGallery(memory: memory, onFocused: order.add)),
      );
      final a = tester
          .widget<FocusableCard>(find.byKey(const ValueKey<String>('card-a')))
          .focusNode!;
      final b = tester
          .widget<FocusableCard>(find.byKey(const ValueKey<String>('card-b')))
          .focusNode!;
      final c = tester
          .widget<FocusableCard>(find.byKey(const ValueKey<String>('card-c')))
          .focusNode!;
      final d = tester
          .widget<FocusableCard>(find.byKey(const ValueKey<String>('card-d')))
          .focusNode!;
      final before = <String, Rect>{
        for (final id in const <String>['card-a', 'card-b', 'card-c', 'card-d'])
          id: tester.getRect(find.byKey(ValueKey<String>(id))),
      };

      a.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(b.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(d.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(c.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(a.hasFocus, isTrue);

      d.requestFocus();
      await tester.pump();
      expect(d.nextFocus(), isTrue);
      await tester.pump();
      expect(a.hasFocus, isTrue);
      expect(
        tester
            .widget<FocusableCard>(
              find.byKey(const ValueKey<String>('card-disabled')),
            )
            .focusNode!
            .skipTraversal,
        isTrue,
      );
      final after = <String, Rect>{
        for (final id in before.keys)
          id: tester.getRect(find.byKey(ValueKey<String>(id))),
      };
      expect(after, before);
      expect(order, containsAllInOrder(<String>['a', 'b', 'd', 'c', 'a']));
      // ignore: avoid_print
      print('traversal order: $order');
      // ignore: avoid_print
      print('geometry before/after: $before -> $after');
    },
  );

  testWidgets('focus memory restores the last item when a surface returns', (
    tester,
  ) async {
    final memory = FocusMemory();
    memory.remember('gallery', 'b');
    await tester.pumpWidget(_app(_FocusGallery(memory: memory)));
    await tester.pump();
    final b = tester
        .widget<FocusableCard>(find.byKey(const ValueKey<String>('card-b')))
        .focusNode!;
    expect(b.hasFocus, isTrue);
    expect(memory.lastFocused('gallery'), 'b');
  });

  test('focus memory is surface-scoped and clearable', () {
    final memory = FocusMemory();
    memory.remember('library', 'movie-1');
    memory.remember('search', 'query-2');
    expect(memory.lastFocused('library'), 'movie-1');
    expect(memory.lastFocused('search'), 'query-2');
    memory.clear('library');
    expect(memory.lastFocused('library'), isNull);
    expect(memory.lastFocused('search'), 'query-2');
  });
}
