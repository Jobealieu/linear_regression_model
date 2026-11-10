import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One thing that went wrong. [field] is the API input name, or null when the
/// problem is not about a single input (no connection, server error).
typedef Problem = ({String? field, String message});

/// Thrown when the API does not return a result. Every problem is already
/// written for the user, so the UI only has to show it.
class ApiException implements Exception {
  const ApiException(this.problems);

  ApiException.general(String message) : problems = [(field: null, message: message)];

  final List<Problem> problems;
}

class Prediction {
  const Prediction({
    required this.totalCostPct,
    required this.totalCostBps,
    required this.sdgGapPctPoints,
    required this.aboveSdgTarget,
    required this.expectedErrorPctPoints,
    required this.model,
    required this.modelVersion,
    required this.inferenceMs,
  });

  factory Prediction.fromJson(Map<String, Object?> json) {
    if (json case {
      'total_cost_pct': final num cost,
      'total_cost_bps': final int bps,
      'sdg_gap_pct_points': final num gap,
      'above_sdg_target': final bool above,
      'expected_error_pct_points': final num rmse,
      'model': final String model,
      'model_version': final int version,
      'inference_ms': final num ms,
    }) {
      return Prediction(
        totalCostPct: cost.toDouble(),
        totalCostBps: bps,
        sdgGapPctPoints: gap.toDouble(),
        aboveSdgTarget: above,
        expectedErrorPctPoints: rmse.toDouble(),
        model: model,
        modelVersion: version,
        inferenceMs: ms.toDouble(),
      );
    }
    throw ApiException.general('The API sent a prediction in an unexpected format.');
  }

  final double totalCostPct;
  final int totalCostBps;
  final double sdgGapPctPoints;
  final bool aboveSdgTarget;
  final double expectedErrorPctPoints;
  final String model;
  final int modelVersion;
  final double inferenceMs;
}

/// The live model's details, from GET /.
class ModelInfo {
  const ModelInfo({
    required this.model,
    required this.modelVersion,
    required this.trainingRows,
    required this.testRmse,
    required this.testR2,
  });

  factory ModelInfo.fromJson(Map<String, Object?> json) {
    if (json case {
      'model': final String model,
      'model_version': final int version,
      'training_rows': final int rows,
      'test_rmse': final num rmse,
      'test_r2': final num r2,
    }) {
      return ModelInfo(
        model: model,
        modelVersion: version,
        trainingRows: rows,
        testRmse: rmse.toDouble(),
        testR2: r2.toDouble(),
      );
    }
    throw ApiException.general('The API sent model details in an unexpected format.');
  }

  final String model;
  final int modelVersion;
  final int trainingRows;
  final double testRmse;
  final double testR2;
}

/// Inputs the API expects as whole numbers. Every other input is text.
const integerInputs = {'speed_hours', 'year'};

/// Builds the /predict body from what the user typed in each field.
///
/// The app does not repeat the API's rules: an empty field is left out and a
/// number that is not whole is sent as typed, so the API's Pydantic model
/// rejects it and the app shows that answer. The rules live in one place.
Map<String, Object> buildRequestBody(Map<String, String> typed) {
  final body = <String, Object>{};
  for (final MapEntry(:key, :value) in typed.entries) {
    final text = value.trim();
    if (text.isEmpty) continue;
    body[key] = integerInputs.contains(key) ? int.tryParse(text) ?? text : text;
  }
  return body;
}

/// Turns one FastAPI/Pydantic validation error into a sentence that starts
/// after the field's label, for example "must be 168 or less, got 500."
Problem describeValidationError(Map<String, Object?> error) {
  final field = switch (error['loc']) {
    [..., final Object last] => '$last',
    _ => null,
  };
  final limits = switch (error['ctx']) {
    final Map<String, Object?> ctx => ctx,
    _ => const <String, Object?>{},
  };
  final got = error['input'];
  final message = switch (error['type']) {
    'missing' => 'is missing. Fill it in.',
    'int_type' || 'int_parsing' || 'int_from_float' => 'must be a whole number, got "$got".',
    'less_than_equal' => 'must be ${limits['le']} or less, got $got.',
    'greater_than_equal' => 'must be ${limits['ge']} or more, got $got.',
    'literal_error' => 'must be one of ${'${limits['expected']}'.replaceAll("'", '')}, got "$got".',
    _ => '${error['msg'] ?? 'is not valid.'}',
  };
  return (field: field, message: message);
}

/// Reads the body of a 422 response: {"detail": [one error per bad input]}.
List<Problem> validationProblems(String body) {
  try {
    if (jsonDecode(body) case {'detail': final List<Object?> errors}) {
      return [
        for (final error in errors)
          if (error case final Map<String, Object?> details) describeValidationError(details),
      ];
    }
  } on FormatException {
    // Not JSON: fall through to the general message below.
  }
  return [(field: null, message: 'The API rejected the input.')];
}

class EntropyApi {
  EntropyApi({http.Client? client, this.baseUrl = defaultBaseUrl}) : _client = client ?? http.Client();

  static const defaultBaseUrl = 'https://entropy-remit-api.onrender.com';

  /// Render's free tier sleeps after 15 idle minutes and can take up to a minute to wake.
  static const timeout = Duration(seconds: 90);

  final String baseUrl;
  final http.Client _client;

  Future<ModelInfo> fetchModelInfo() async {
    final response = await _send(() => _client.get(Uri.parse('$baseUrl/')));
    return ModelInfo.fromJson(_decodeObject(response.body));
  }

  /// [typed] maps each API input name to the text in its field.
  Future<Prediction> predict(Map<String, String> typed) async {
    final response = await _send(
      () => _client.post(
        Uri.parse('$baseUrl/predict'),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(buildRequestBody(typed)),
      ),
    );
    return Prediction.fromJson(_decodeObject(response.body));
  }

  /// Sends one request. Any failure becomes an [ApiException] the UI can show.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException.general(
        'No answer within ${timeout.inSeconds} seconds. The free server may still be waking up, press Predict again.',
      );
    } on http.ClientException {
      throw ApiException.general('Could not reach the API. Check the internet connection and try again.');
    }
    return switch (response.statusCode) {
      200 => response,
      422 => throw ApiException(validationProblems(response.body)),
      final status => throw ApiException.general('The API answered with HTTP $status. Try again in a moment.'),
    };
  }

  Map<String, Object?> _decodeObject(String body) {
    try {
      if (jsonDecode(body) case final Map<String, Object?> json) return json;
    } on FormatException {
      // Not JSON: handled below.
    }
    throw ApiException.general('The API sent a response the app could not read.');
  }
}
