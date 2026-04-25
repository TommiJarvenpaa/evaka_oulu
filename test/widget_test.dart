import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evaka_oulu/main.dart';

void main() {
  testWidgets('App rendaa ilman kaatumista', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EvakaApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
