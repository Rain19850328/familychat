import 'web_push_types.dart';

const bool browserPushSupported = false;

Future<BrowserPushSetupResult> ensureBrowserPushSubscription({
  required String pushConfigUrl,
  required String serviceWorkerPath,
}) async {
  return const BrowserPushSetupResult(
    status: BrowserPushSetupStatus.unsupported,
  );
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
