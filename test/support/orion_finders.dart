import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_typography.dart';

/// Finds an [OrionTitle] by the copy it was given, not the caps it renders.
///
/// [OrionTitle] uppercases for display only, so `find.text` against real copy
/// misses it. Matching the widget's own [OrionTitle.data] keeps these tests
/// asserting intent, and survives a future change to how titles are cased.
Finder findOrionTitle(String data) => find.byWidgetPredicate(
  (widget) => widget is OrionTitle && widget.data == data,
  description: 'OrionTitle("$data")',
);
