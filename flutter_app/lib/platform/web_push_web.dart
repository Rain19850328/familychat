// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'web_push_types.dart';

const bool browserPushSupported = true;

Future<BrowserPushSetupResult> ensureBrowserPushSubscription({
  required String pushConfigUrl,
  required String serviceWorkerPath,
}) async {
  final container = html.window.navigator.serviceWorker;
  if (container == null || !html.Notification.supported) {
    return const BrowserPushSetupResult(
      status: BrowserPushSetupStatus.unsupported,
    );
  }

  final permission = await html.Notification.requestPermission();
  if (permission != 'granted') {
    return BrowserPushSetupResult(
      status: BrowserPushSetupStatus.permissionDenied,
      detail: permission,
    );
  }

  try {
    final registration = await container.register(serviceWorkerPath);
    final pushManager = registration.pushManager;
    if (pushManager == null) {
      return const BrowserPushSetupResult(
        status: BrowserPushSetupStatus.unavailable,
        detail: 'missing_push_manager',
      );
    }

    html.PushSubscription? subscription;
    try {
      subscription = await pushManager.getSubscription();
    } catch (_) {
      subscription = null;
    }

    if (subscription == null) {
      final configRequest = await html.HttpRequest.request(
        pushConfigUrl,
        method: 'GET',
        requestHeaders: <String, String>{
          'Accept': 'application/json',
        },
      );
      final config = jsonDecode(configRequest.responseText ?? '{}') as Map;
      final publicKey = config['publicKey']?.toString() ?? '';
      if (publicKey.isEmpty) {
        return const BrowserPushSetupResult(
          status: BrowserPushSetupStatus.unavailable,
          detail: 'missing_public_key',
        );
      }

      subscription = await pushManager.subscribe(<String, Object>{
        'userVisibleOnly': true,
        'applicationServerKey': _urlBase64ToUint8List(publicKey),
      });
    }

    final endpoint = subscription.endpoint ?? '';
    final p256dh = _encodeSubscriptionKey(subscription.getKey('p256dh'));
    final auth = _encodeSubscriptionKey(subscription.getKey('auth'));
    if (endpoint.isEmpty || p256dh.isEmpty || auth.isEmpty) {
      return const BrowserPushSetupResult(
        status: BrowserPushSetupStatus.unavailable,
        detail: 'invalid_subscription',
      );
    }

    return BrowserPushSetupResult(
      status: BrowserPushSetupStatus.subscribed,
      subscription: BrowserPushSubscription(
        endpoint: endpoint,
        p256dh: p256dh,
        auth: auth,
        userAgent: html.window.navigator.userAgent,
      ),
    );
  } catch (error) {
    return BrowserPushSetupResult(
      status: BrowserPushSetupStatus.unavailable,
      detail: error.toString(),
    );
  }
}

Future<String?> removeBrowserPushSubscription({
  required String serviceWorkerPath,
}) async {
  final container = html.window.navigator.serviceWorker;
  if (container == null) {
    return null;
  }

  html.ServiceWorkerRegistration? registration;
  try {
    registration = await container.getRegistration();
  } catch (_) {
    registration = null;
  }
  if (registration == null || registration.pushManager == null) {
    return null;
  }

  html.PushSubscription? subscription;
  try {
    subscription = await registration.pushManager!.getSubscription();
  } catch (_) {
    subscription = null;
  }
  if (subscription == null) {
    return null;
  }

  final endpoint = subscription.endpoint;
  await subscription.unsubscribe();
  return endpoint;
}

PushNavigationIntent? getPendingPushNavigationIntent() {
  final uri = Uri.base;
  if (uri.queryParameters['pushOpen'] != '1') {
    return null;
  }

  final familyId = uri.queryParameters['familyId']?.trim() ?? '';
  final roomId = uri.queryParameters['roomId']?.trim() ?? '';
  if (familyId.isEmpty || roomId.isEmpty) {
    return null;
  }

  final messageId = uri.queryParameters['messageId']?.trim();
  return PushNavigationIntent(
    familyId: familyId,
    roomId: roomId,
    messageId: messageId == null || messageId.isEmpty ? null : messageId,
  );
}

void clearPendingPushNavigationIntent() {
  final uri = Uri.base;
  if (uri.queryParameters['pushOpen'] != '1') {
    return;
  }

  final updatedQuery = Map<String, String>.from(uri.queryParameters)
    ..remove('pushOpen')
    ..remove('familyId')
    ..remove('roomId')
    ..remove('messageId');
  final cleanedUri = uri.replace(queryParameters: updatedQuery.isEmpty ? null : updatedQuery);
  html.window.history.replaceState(null, html.document.title, cleanedUri.toString());
}

Uint8List _urlBase64ToUint8List(String input) {
  final normalized = base64.normalize(
    input.replaceAll('-', '+').replaceAll('_', '/'),
  );
  return base64Decode(normalized);
}

String _encodeSubscriptionKey(ByteBuffer? buffer) {
  if (buffer == null) {
    return '';
  }
  final bytes = Uint8List.view(buffer);
  return base64Url.encode(bytes).replaceAll('=', '');
}
