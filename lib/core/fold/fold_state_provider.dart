import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';

/// Shared posture boundary. The platform bridge reports settled observations
/// here when available; until then the shell remains in an honest unknown state.
final foldStateControllerProvider = Provider<FoldStateController>((ref) {
  final controller = FoldStateController();
  ref.onDispose(controller.dispose);
  return controller;
});
