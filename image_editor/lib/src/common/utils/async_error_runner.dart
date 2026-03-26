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
