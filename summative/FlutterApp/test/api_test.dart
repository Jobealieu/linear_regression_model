import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entropy/api.dart';

/// Real bodies returned by https://entropy-remit-api.onrender.com/predict (destination list shortened).
const outOfRangeAndMissing =
    '{"detail":[{"type":"literal_error","loc":["body","destination_country"],'
    '"msg":"Input should be \'AGO\', \'BEN\' or \'ZWE\'","input":"FRA","ctx":{"expected":"\'AGO\', \'BEN\' or \'ZWE\'"}},'
    '{"type":"less_than_equal","loc":["body","speed_hours"],"msg":"Input should be less than or equal to 168",'
    '"input":500,"ctx":{"le":168}},'
    '{"type":"missing","loc":["body","year"],"msg":"Field required","input":{"source_country":"USA"}}]}';
const wrongTypeAndTooLow =
    '{"detail":[{"type":"int_type","loc":["body","speed_hours"],"msg":"Input should be a valid integer","input":"fast"},'
    '{"type":"greater_than_equal","loc":["body","year"],"msg":"Input should be greater than or equal to 2016",'
    '"input":2010,"ctx":{"ge":2016}}]}';
const predictionBody =
    '{"total_cost_pct":8.58,"total_cost_bps":858,"sdg_gap_pct_points":5.58,"above_sdg_target":true,'
    '"expected_error_pct_points":2.722,"model":"RandomForestRegressor","model_version":1,"inference_ms":12.3}';

EntropyApi apiAnswering(int status, String body) =>
    EntropyApi(client: MockClient((_) async => http.Response(body, status)));

void main() {
  group('buildRequestBody', () {
    test('sends whole numbers as numbers and trims text', () {
      expect(buildRequestBody({'year': ' 2025 ', 'speed_hours': '24', 'firm_type': ' mto '}),
          {'year': 2025, 'speed_hours': 24, 'firm_type': 'mto'});
    });

    test('leaves out empty fields and keeps non-numbers as typed, so the API reports them', () {
      expect(buildRequestBody({'year': '', 'speed_hours': '24.5', 'transparent': '  '}), {'speed_hours': '24.5'});
    });
  });

  group('predict', () {
    test('posts JSON to /predict and reads the prediction', () async {
      late http.Request sent;
      final api = EntropyApi(client: MockClient((request) async {
        sent = request;
        return http.Response(predictionBody, 200);
      }));

      final prediction = await api.predict({'year': '2025', 'firm_type': 'MTO'});

      expect(sent.url.toString(), 'https://entropy-remit-api.onrender.com/predict');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {'year': 2025, 'firm_type': 'MTO'});
      expect(prediction.totalCostPct, 8.58);
      expect(prediction.totalCostBps, 858);
      expect(prediction.aboveSdgTarget, isTrue);
      expect(prediction.modelVersion, 1);
    });

    test('turns missing and out-of-range values into readable problems', () async {
      final error = await expectApiException(apiAnswering(422, outOfRangeAndMissing));
      expect(error.problems, [
        (field: 'destination_country', message: 'must be one of AGO, BEN or ZWE, got "FRA".'),
        (field: 'speed_hours', message: 'must be 168 or less, got 500.'),
        (field: 'year', message: 'is missing. Fill it in.'),
      ]);
    });

    test('turns a wrong type and a too-low value into readable problems', () async {
      final error = await expectApiException(apiAnswering(422, wrongTypeAndTooLow));
      expect(error.problems, [
        (field: 'speed_hours', message: 'must be a whole number, got "fast".'),
        (field: 'year', message: 'must be 2016 or more, got 2010.'),
      ]);
    });

    test('explains a server error', () async {
      final error = await expectApiException(apiAnswering(502, '<html>Bad gateway</html>'));
      expect(error.problems.single.field, isNull);
      expect(error.problems.single.message, contains('HTTP 502'));
    });

    test('explains a lost connection', () async {
      final api = EntropyApi(client: MockClient((_) => throw http.ClientException('Connection refused')));
      final error = await expectApiException(api);
      expect(error.problems.single.message, startsWith('Could not reach the API'));
    });
  });

  test('fetchModelInfo reads GET /', () async {
    final api = apiAnswering(200,
        '{"model":"RandomForestRegressor","model_version":2,"training_rows":41920,"test_rmse":2.736,"test_r2":0.78}');
    final info = await api.fetchModelInfo();
    expect((info.model, info.modelVersion, info.trainingRows, info.testRmse), ('RandomForestRegressor', 2, 41920, 2.736));
  });
}

Future<ApiException> expectApiException(EntropyApi api) async {
  try {
    await api.predict({'year': '2025'});
  } on ApiException catch (error) {
    return error;
  }
  fail('predict() should have thrown an ApiException');
}
