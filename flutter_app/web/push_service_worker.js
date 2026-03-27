self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  const payload = parsePayload(event);
  const title = payload.title || 'Family Space';
  const options = {
    body: payload.body || '',
    tag: payload.tag || undefined,
    data: payload.data || {},
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    renotify: true,
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const targetUrl = new URL(self.registration.scope);
  targetUrl.searchParams.set('pushOpen', '1');
  if (data.familyId) {
    targetUrl.searchParams.set('familyId', data.familyId);
  }
  if (data.roomId) {
    targetUrl.searchParams.set('roomId', data.roomId);
  }
  if (data.messageId) {
    targetUrl.searchParams.set('messageId', data.messageId);
  }

  event.waitUntil(openTargetClient(targetUrl.toString()));
});

function parsePayload(event) {
  if (!event.data) {
    return {};
  }

  try {
    return event.data.json() || {};
  } catch (_) {
    return {
      body: event.data.text(),
    };
  }
}

async function openTargetClient(targetUrl) {
  const clients = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });

  for (const client of clients) {
    if ('navigate' in client) {
      await client.navigate(targetUrl);
    }
    if ('focus' in client) {
      await client.focus();
    }
    return;
  }

  await self.clients.openWindow(targetUrl);
}
