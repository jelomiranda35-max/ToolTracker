import 'package:flutter_test/flutter_test.dart';
import 'package:amtec_tool_tracker/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ToolTrackerApp());
  });
}