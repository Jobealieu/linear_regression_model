import 'dart:async';

import 'package:flutter/material.dart';

import 'package:entropy/api.dart';
import 'package:entropy/output_panel.dart';

/// One text field. [key] is the API input name and [hint] is a valid example,
/// which the "fill sample" button also uses.
typedef InputField = ({String key, String label, String hint, String help, TextInputType keyboard});

/// The 10 inputs the model needs, in three groups. One text field each.
const inputSections = <(String, List<InputField>)>[
  ('corridor', [
    (key: 'source_country', label: 'Sending country', hint: 'USA',
     help: 'ISO3 code: USA, GBR, FRA, ZAF, SAU ...', keyboard: TextInputType.text),
    (key: 'destination_country', label: 'Receiving country (Africa)', hint: 'GMB',
     help: 'ISO3 code: GMB, NGA, KEN, GHA, SEN ...', keyboard: TextInputType.text),
    (key: 'year', label: 'Year', hint: '2025', help: '2016 to 2030', keyboard: TextInputType.number),
  ]),
  ('provider', [
    (key: 'firm_type', label: 'Provider type', hint: 'MTO',
     help: 'BANK, MTO, MOBILE_OPERATOR, POST, NON_BANK_FI, MULTI', keyboard: TextInputType.text),
    (key: 'transparent', label: 'Exchange rate disclosed', hint: 'yes', help: 'yes or no', keyboard: TextInputType.text),
    (key: 'network_coverage', label: 'Pickup network coverage', hint: 'HIGH',
     help: 'HIGH, MEDIUM, LOW', keyboard: TextInputType.text),
  ]),
  ('transfer', [
    (key: 'payment_instrument', label: 'Sender pays with', hint: 'CARD',
     help: 'CASH, BANK_ACCOUNT, CARD, MOBILE_MONEY, MULTI', keyboard: TextInputType.text),
    (key: 'access_point', label: 'Sender starts at', hint: 'ONLINE',
     help: 'AGENT, ONLINE, BRANCH, CALL_CENTER, POST_OFFICE, MOBILE_APP, MULTI', keyboard: TextInputType.text),
    (key: 'pickup_method', label: 'Receiver gets money as', hint: 'MOBILE_WALLET',
     help: 'CASH, BANK_ACCOUNT, MOBILE_WALLET', keyboard: TextInputType.text),
    (key: 'speed_hours', label: 'Delivery time (hours)', hint: '1',
     help: '1 to 168 (one week)', keyboard: TextInputType.number),
  ]),
];

final inputFields = [for (final (_, fields) in inputSections) ...fields];
final _labels = {for (final field in inputFields) field.key: field.label};
final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// "Year" + "is missing. Fill it in." -> "Year is missing. Fill it in."
String readable(Problem problem) => switch (_labels[problem.field]) {
  final String label => '$label ${problem.message}',
  null => problem.message,
};

class PredictPage extends StatefulWidget {
  const PredictPage({super.key, required this.api});

  final EntropyApi api;

  @override
  State<PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<PredictPage> {
  final _controllers = {for (final field in inputFields) field.key: TextEditingController()};
  final _scroll = ScrollController();
  late final Future<ModelInfo> _modelInfo;
  Output _output = const Idle();

  @override
  void initState() {
    super.initState();
    // Asking for the model details also wakes the free Render server while the user types.
    _modelInfo = widget.api.fetchModelInfo();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _fillSample() {
    for (final field in inputFields) {
      _controllers[field.key]?.text = field.hint;
    }
  }

  Future<void> _predict() async {
    FocusScope.of(context).unfocus(); // hide the keyboard so the result is visible
    setState(() => _output = const Loading());
    final typed = {for (final MapEntry(:key, :value) in _controllers.entries) key: value.text.trim()};
    final corridor = '${typed['source_country']} -> ${typed['destination_country']}'.toUpperCase();

    Output next;
    try {
      next = Success(await widget.api.predict(typed), corridor: corridor);
    } on ApiException catch (error) {
      next = Failure([for (final problem in error.problems) readable(problem)]);
    }

    if (!mounted) return;
    setState(() => _output = next);
    _scrollToOutput();
  }

  void _scrollToOutput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(_scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _output is Loading;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onFillSample: isLoading ? null : _fillSample),
                  const SizedBox(height: 16),
                  _ModelPanel(modelInfo: _modelInfo, host: Uri.parse(widget.api.baseUrl).host),
                  for (final (index, (title, fields)) in inputSections.indexed) ...[
                    const SizedBox(height: 24),
                    _SectionTitle('// 0${index + 1} $title'),
                    for (final field in fields) ...[
                      const SizedBox(height: 12),
                      _InputTextField(
                        field: field,
                        controller: _controllers[field.key],
                        onDone: field == inputFields.last && !isLoading ? _predict : null,
                      ),
                    ],
                  ],
                  const SizedBox(height: 28),
                  FilledButton(onPressed: isLoading ? null : _predict, child: const Text('Predict')),
                  const SizedBox(height: 16),
                  OutputPanel(output: _output),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onFillSample});

  final VoidCallback? onFillSample;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('root@entropy:~# predict', style: TextStyle(color: colors.primary, fontSize: 13)),
            ),
            TextButton(onPressed: onFillSample, child: const Text('fill sample')),
          ],
        ),
        Text(
          'ENTROPY',
          style: text.headlineMedium?.copyWith(color: colors.onSurface, fontWeight: FontWeight.w700, letterSpacing: 6),
        ),
        const SizedBox(height: 6),
        Text(
          'Predicts the all-in cost (fees + exchange-rate margin) of sending USD 200 into an African country.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

/// The live model's details from GET /, in blue.
class _ModelPanel extends StatelessWidget {
  const _ModelPanel({required this.modelInfo, required this.host});

  final Future<ModelInfo> modelInfo;
  final String host;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(left: BorderSide(color: colors.secondary, width: 3)),
      ),
      child: FutureBuilder<ModelInfo>(
        future: modelInfo,
        builder: (context, snapshot) {
          final lines = switch (snapshot) {
            AsyncSnapshot(:final data?) => [
              '${data.model} v${data.modelVersion}',
              'test RMSE ${data.testRmse.toStringAsFixed(2)} pts | R² ${data.testR2.toStringAsFixed(2)}',
              'trained on ${'${data.trainingRows}'.replaceAll(_thousands, ',')} World Bank quotes',
            ],
            AsyncSnapshot(hasError: true) => ['API not reachable yet. Predict will try again.'],
            _ => ['GET /  waking the API ...'],
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('[ model ]  $host', style: TextStyle(color: colors.secondary, fontSize: 12)),
              const SizedBox(height: 6),
              for (final line in lines) Text(line, style: TextStyle(color: colors.onSurface, fontSize: 13, height: 1.5)),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13));
  }
}

class _InputTextField extends StatelessWidget {
  const _InputTextField({required this.field, required this.controller, required this.onDone});

  final InputField field;
  final TextEditingController? controller;
  final VoidCallback? onDone; // set on the last field: "done" on the keyboard runs Predict

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: field.keyboard,
      textCapitalization: TextCapitalization.characters, // the API accepts any case
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: onDone == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: onDone == null ? null : (_) => onDone?.call(),
      decoration: InputDecoration(labelText: field.label, hintText: 'e.g. ${field.hint}', helperText: field.help),
    );
  }
}
