typedef WindowInteractionListener = void Function(bool isInteractive);

class WindowInteractionObserver {
  const WindowInteractionObserver._();

  void dispose() {}
}

bool currentWindowInteractionState() {
  return true;
}

WindowInteractionObserver observeWindowInteraction(
  WindowInteractionListener listener,
) {
  return const WindowInteractionObserver._();
}
