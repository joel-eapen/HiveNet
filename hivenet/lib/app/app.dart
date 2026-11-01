import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pairing_prompt_host.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class HiveNetApp extends ConsumerWidget {
  const HiveNetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'HiveNet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => PairingPromptHost(child: child ?? const SizedBox()),
    );
  }
}
