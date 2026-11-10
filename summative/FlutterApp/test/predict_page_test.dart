import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entropy/api.dart';
import 'package:entropy/main.dart';

const modelInfoBody =
    '{"model":"RandomForestRegressor","model_version":1,"training_rows":40198,"test_rmse":2.722,"test_r2":0.782}';

/// Starts the app with a fake API: GET / returns the model details and
/// POST /predict returns [predictStatus] with [predictBody].
Future<void> startApp(WidgetTester tester, {int predictStatus = 200, String predictBody = ''}) async {
  final client = MockClient((request) async => request.url.path == '/predict'
      ? http.Response(predictBody, predictStatus)
      : http.Response(modelInfoBody, 200));
  await tester.pumpWidget(EntropyApp(api: EntropyApi(client: client)));
  await tester.pumpAndSettle();
}

Future<void> tapPredict(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Predict'));
  await tester.tap(find.widgetWithText(FilledButton, 'Predict'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows one labelled text field per model input and a Predict button', (tester) async {
    await startApp(tester);

    expect(find.byType(TextField), findsNWidgets(10));
    for (final label in ['Sending country', 'Receiving country (Africa)', 'Year', 'Provider type',
        'Exchange rate disclosed', 'Pickup network coverage', 'Sender pays with', 'Sender starts at',
        'Receiver gets money as', 'Delivery time (hours)']) {
      expect(find.widgetWithText(TextField, label), findsOneWidget, reason: label);
    }
    expect(find.widgetWithText(FilledButton, 'Predict'), findsOneWidget);
    expect(find.text('RandomForestRegressor v1'), findsOneWidget); // model panel filled from GET /
  });

  testWidgets('shows the predicted cost in the output area', (tester) async {
    await startApp(tester, predictBody:
        '{"total_cost_pct":8.58,"total_cost_bps":858,"sdg_gap_pct_points":5.58,"above_sdg_target":true,'
        '"expected_error_pct_points":2.722,"model":"RandomForestRegressor","model_version":1,"inference_ms":12.3}');

    await tester.tap(find.text('fill sample'));
    await tapPredict(tester);

    expect(find.text('8.58%'), findsOneWidget);
    expect(find.text('858 bps'), findsOneWidget);
    expect(find.text('5.58 pts above the 3% SDG target'), findsOneWidget);
    expect(find.textContaining('USA -> GMB'), findsOneWidget);
  });

  testWidgets('shows a readable error in the output area when the API rejects the input', (tester) async {
    await startApp(tester, predictStatus: 422, predictBody:
        '{"detail":[{"type":"less_than_equal","loc":["body","speed_hours"],'
        '"msg":"Input should be less than or equal to 168","input":500,"ctx":{"le":168}},'
        '{"type":"missing","loc":["body","year"],"msg":"Field required","input":{}}]}');

    await tapPredict(tester);

    expect(find.text('ERROR  no prediction'), findsOneWidget);
    expect(find.text('- Delivery time (hours) must be 168 or less, got 500.'), findsOneWidget);
    expect(find.text('- Year is missing. Fill it in.'), findsOneWidget);
  });
}
