import 'package:flutter/material.dart';

import 'package:entropy/api.dart';

/// What the display area shows. Only one of these can be true at a time.
sealed class Output {
  const Output();
}

final class Idle extends Output {
  const Idle();
}

final class Loading extends Output {
  const Loading();
}

final class Success extends Output {
  const Success(this.prediction, {required this.corridor});

  final Prediction prediction;
  final String corridor; // e.g. "USA -> GMB"
}

final class Failure extends Output {
  const Failure(this.lines);

  final List<String> lines; // readable sentences, one per problem
}

/// The single display area for both the predicted value and error messages.
class OutputPanel extends StatelessWidget {
  const OutputPanel({super.key, required this.output});

  final Output output;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = switch (output) {
      Success() => colors.primary,
      Failure() => colors.error,
      Idle() || Loading() => colors.outline,
    };

    return Semantics(
      container: true,
      liveRegion: true, // screen readers announce the new result
      label: 'Prediction output',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          border: Border.all(color: borderColor),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('> output', style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            switch (output) {
              Idle() => const _IdleView(),
              Loading() => const _LoadingView(),
              Success(:final prediction, :final corridor) => _SuccessView(prediction: prediction, corridor: corridor),
              Failure(:final lines) => _FailureView(lines: lines),
            },
          ],
        ),
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Fill in the 10 fields and press Predict.\nThe predicted cost appears here.',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('POST /predict ...', style: TextStyle(color: colors.primary)),
        const SizedBox(height: 8),
        LinearProgressIndicator(color: colors.primary, backgroundColor: colors.outlineVariant),
        const SizedBox(height: 8),
        Text(
          'The first request can take up to a minute while the free server wakes up.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.prediction, required this.corridor});

  final Prediction prediction;
  final String corridor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final gap = prediction.sdgGapPctPoints.abs().toStringAsFixed(2);
    final side = prediction.aboveSdgTarget ? 'above' : 'below';
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$corridor  all-in cost of sending USD 200', style: TextStyle(color: colors.tertiary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          '${prediction.totalCostPct.toStringAsFixed(2)}%',
          style: text.displaySmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
        ),
        Text('${prediction.totalCostBps} bps', style: TextStyle(color: colors.tertiary, fontSize: 16)),
        const SizedBox(height: 12),
        Text('$gap pts $side the 3% SDG target', style: TextStyle(color: colors.onSurface)),
        const SizedBox(height: 4),
        Text('typical error ±${prediction.expectedErrorPctPoints.toStringAsFixed(2)} pts (test RMSE)', style: muted),
        Text(
          '${prediction.model} v${prediction.modelVersion} | ${prediction.inferenceMs.toStringAsFixed(0)} ms',
          style: muted,
        ),
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ERROR  no prediction', style: TextStyle(color: colors.error, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('- $line', style: TextStyle(color: colors.error, height: 1.4)),
          ),
      ],
    );
  }
}
