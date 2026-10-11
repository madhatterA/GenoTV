import 'package:flutter/material.dart';

/// A small focus-aware surface wrapper used by later screens.
class FocusScaffold extends StatelessWidget {
  const FocusScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: FocusScope(autofocus: true, child: child));
}
