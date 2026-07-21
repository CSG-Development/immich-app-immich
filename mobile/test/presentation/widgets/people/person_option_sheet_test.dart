import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/presentation/widgets/people/person_option_sheet.widget.dart';

class _FavoriteSheetHarness extends StatefulWidget {
  const _FavoriteSheetHarness();

  @override
  State<_FavoriteSheetHarness> createState() => _FavoriteSheetHarnessState();
}

class _FavoriteSheetHarnessState extends State<_FavoriteSheetHarness> {
  bool isFavorite = false;

  @override
  Widget build(BuildContext context) {
    return PersonOptionSheet(isFavorite: isFavorite, onToggleFavorite: () => setState(() => isFavorite = !isFavorite));
  }
}

void main() {
  testWidgets('favorite action label reacts to state changes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _FavoriteSheetHarness())));

    expect(find.text('to_favorite'), findsOneWidget);
    expect(find.text('unfavorite'), findsNothing);

    await tester.tap(find.text('to_favorite'));
    await tester.pump();

    expect(find.text('to_favorite'), findsNothing);
    expect(find.text('unfavorite'), findsOneWidget);
  });
}
