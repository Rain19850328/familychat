// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

typedef WindowInteractionListener = void Function(bool isInteractive);

bool _windowHasFocus = true;

class WindowInteractionObserver {
  WindowInteractionObserver._(this._dispose);

  final void Function() _dispose;

  void dispose() {
    _dispose();
  }
}

bool currentWindowInteractionState() {
  final visibilityState = html.document.visibilityState;
  final isVisible = visibilityState == 'visible';
  return isVisible && _windowHasFocus;
}

WindowInteractionObserver observeWindowInteraction(
  WindowInteractionListener listener,
) {
  void emit([html.Event? event]) {
    if (event?.type == 'focus') {
      _windowHasFocus = true;
    } else if (event?.type == 'blur') {
      _windowHasFocus = false;
    } else if (event?.type == 'visibilitychange' &&
        html.document.visibilityState != 'visible') {
      _windowHasFocus = false;
    }
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
