import 'web_push_types.dart';

const bool browserPushSupported = false;

Future<BrowserPushSubscription?> ensureBrowserPushSubscription({
  required String pushConfigUrl,
  required String serviceWorkerPath,
}) async {
  return null;
}

Future<String?> removeBrowserPushSubscription({
  required String serviceWorkerPath,
}) async {
  return null;
}

PushNavigationIntent? getPendingPushNavigationIntent() {
  return null;
}

void clearPendingPushNavigationIntent() {}
