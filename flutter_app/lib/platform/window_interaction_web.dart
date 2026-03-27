// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

typedef WindowInteractionListener = void Function(bool isInteractive);

class WindowInteractionObserver {
  WindowInteractionObserver._(this._dispose);

  final void Function() _dispose;

  void dispose() {
    _dispose();
  }
}

bool currentWindowInteractionState() {
  final visibilityState = html.document.visibilityState;
  final isVisible = visibilityState == null || visibilityState == 'visible';
  bool hasFocus = true;
  try {
    hasFocus = html.document.hasFocus();
  } catch (_) {
    hasFocus = true;
  }
  return isVisible && hasFocus;
}

WindowInteractionObserver observeWindowInteraction(
  WindowInteractionListener listener,
) {
  void emit([html.Event? _]) {
    listener(currentWindowInteractionState());
  }

  html.document.addEventListener('visibilitychange', emit);
  html.window.addEventListener('focus', emit);
  html.window.addEventListener('blur', emit);
  emit();

  return WindowInteractionObserver._(() {
    html.document.removeEventListener('visibilitychange', emit);
    html.window.removeEventListener('focus', emit);
    html.window.removeEventListener('blur', emit);
  });
}
