import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/app.dart';

void main() {
  testWidgets('renders the three core voice modes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: VoxWriteApp()));
    await tester.pumpAndSettle();

    expect(find.text('开口起草，让文字自然成形'), findsOneWidget);
    expect(find.text('口述'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('问与改写'), findsOneWidget);
  });
}
