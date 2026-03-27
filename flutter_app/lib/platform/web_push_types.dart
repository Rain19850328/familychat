class BrowserPushSubscription {
  const BrowserPushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
    required this.userAgent,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
  final String userAgent;
}

enum BrowserPushSetupStatus {
  subscribed,
  unsupported,
  permissionDenied,
  unavailable,
}

class BrowserPushSetupResult {
  const BrowserPushSetupResult({
    required this.status,
    this.subscription,
    this.detail,
  });

  final BrowserPushSetupStatus status;
  final BrowserPushSubscription? subscription;
  final String? detail;

  bool get isSubscribed => subscription != null;
}

class PushNavigationIntent {
  const PushNavigationIntent({
    required this.familyId,
    required this.roomId,
    this.messageId,
  });

  final String familyId;
  final String roomId;
  final String? messageId;
}
