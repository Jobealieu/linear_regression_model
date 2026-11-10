import 'package:flutter/material.dart';

import 'package:entropy/api.dart';
import 'package:entropy/predict_page.dart';
import 'package:entropy/theme.dart';

void main() => runApp(EntropyApp(api: EntropyApi()));

class EntropyApp extends StatelessWidget {
  const EntropyApp({super.key, required this.api});

  final EntropyApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ENTROPY',
      debugShowCheckedModeBanner: false,
      theme: entropyTheme(),
      home: PredictPage(api: api),
    );
  }
}
