import 'dart:async';

import 'package:flutter/material.dart';

typedef ErrorMessageBuilder = String Function(Object error, StackTrace stackTrace);

/// Runs async work with shared error handling and optional user feedback.
Future<T?> runWithBusyAndError<T>({
  required BuildContext context,
  required State state,
  required Future<T> Function() run,
  required VoidCallback setBusy,
  required VoidCallback clearBusy,
  ErrorMessageBuilder? errorMessageBuilder,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  setBusy();
  // Yield one frame so loading UI becomes visible before expensive work starts.
  await WidgetsBinding.instance.endOfFrame;
  try {
    return await run();
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    if (state.mounted) {
      final message = errorMessageBuilder?.call(error, stackTrace) ?? 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    return null;
  } finally {
    if (state.mounted) {
      clearBusy();
    }
  }
}

/// Runs async work while toggling a busy state and optionally yielding one UI frame first.
Future<void> runBusyUiFlow({
  required State state,
  required VoidCallback setBusy,
  required VoidCallback clearBusy,
  required Future<void> Function() run,
  bool waitFrameBeforeRun = true,
}) async {
  setBusy();
  if (waitFrameBeforeRun) {
    await WidgetsBinding.instance.endOfFrame;
  }
  try {
    await run();
  } finally {
    if (state.mounted) {
      clearBusy();
    }
  }
}

/// Runs completion callback and pops route with one-frame handoff to avoid flicker.
Future<void> completeAndPop({
  required State state,
  required BuildContext context,
  required Future<void> Function() onComplete,
  bool waitFrameBeforePop = true,
}) async {
  await onComplete();
  if (waitFrameBeforePop) {
    await WidgetsBinding.instance.endOfFrame;
  }
  if (state.mounted && Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}
