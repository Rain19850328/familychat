const CACHE_NAME = "familychat-shell-v6";
const BACKGROUND_STATE_CACHE = "familychat-background-v1";
const BACKGROUND_STATE_URL = "https://familychat.local/background-state";
const BACKGROUND_SYNC_TAG = "familychat-message-check";
const APP_SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./supabase.config.js",
  "./manifest.webmanifest",
  "./icons/apple-touch-icon.png",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-192.svg",
  "./icons/icon-512.svg",
];
const NETWORK_FIRST_PATHS = [
  "/app.js",
  "/styles.css",
  "/manifest.webmanifest",
  "/supabase.config.js",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key !== CACHE_NAME && key !== BACKGROUND_STATE_CACHE)
        .map((key) => caches.delete(key)),
    );
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") {
    return;
  }

  const requestUrl = new URL(event.request.url);
  if (NETWORK_FIRST_PATHS.some((pathname) => requestUrl.pathname.endsWith(pathname))) {
    const cacheKey = requestUrl.pathname === "/" ? "./index.html" : `.${requestUrl.pathname}`;
    event.respondWith(
      fetch(event.request, { cache: "no-store" })
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(cacheKey, copy));
          return response;
        })
        .catch(() => caches.match(cacheKey)),
    );
    return;
  }

  if (event.request.mode === "navigate") {
    event.respondWith(fetch(event.request).catch(() => caches.match("./index.html")));
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) {
        return cached;
      }
      return fetch(event.request).then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        return response;
      });
    }),
  );
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SYNC_SESSION") {
    event.waitUntil(syncBackgroundState(event.data.payload));
  }

  if (event.data?.type === "CLEAR_SESSION") {
    event.waitUntil(clearBackgroundState());
  }
});

self.addEventListener("periodicsync", (event) => {
  if (event.tag === BACKGROUND_SYNC_TAG) {
    event.waitUntil(checkForBackgroundMessages());
  }
});

self.addEventListener("sync", (event) => {
  if (event.tag === BACKGROUND_SYNC_TAG) {
    event.waitUntil(checkForBackgroundMessages());
  }
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const windowClients = await clients.matchAll({
      type: "window",
      includeUncontrolled: true,
    });

    const visibleClient = windowClients.find((client) => "focus" in client);
    if (visibleClient) {
      return visibleClient.focus();
    }

    return clients.openWindow("./");
  })());
});

async function syncBackgroundState(payload) {
  if (!payload?.config?.url || !payload?.config?.anonKey || !payload?.session) {
    await clearBackgroundState();
    return;
  }

  const currentState = await readBackgroundState();
  const sessionKey = `${payload.session.familyId}:${payload.session.memberId}`;

  await writeBackgroundState({
    sessionKey,
    config: payload.config,
    session: payload.session,
    notificationPermission: payload.notificationPermission ?? "default",
    lastMessageByRoom: payload.lastMessageByRoom ?? currentState?.lastMessageByRoom ?? {},
  });
}

async function clearBackgroundState() {
  const cache = await caches.open(BACKGROUND_STATE_CACHE);
  await cache.delete(BACKGROUND_STATE_URL);
}

async function readBackgroundState() {
  const cache = await caches.open(BACKGROUND_STATE_CACHE);
  const response = await cache.match(BACKGROUND_STATE_URL);
  if (!response) {
    return null;
  }

  try {
    return await response.json();
  } catch {
    return null;
  }
}

async function writeBackgroundState(state) {
  const cache = await caches.open(BACKGROUND_STATE_CACHE);
  await cache.put(
    BACKGROUND_STATE_URL,
    new Response(JSON.stringify(state), {
      headers: {
        "Content-Type": "application/json",
      },
    }),
  );
}

async function checkForBackgroundMessages() {
  const state = await readBackgroundState();
  if (!state?.config?.url || !state?.config?.anonKey || !state?.session) {
    return;
  }

  if (state.notificationPermission !== "granted") {
    return;
  }

  const family = await fetchFamilySnapshot(state.config, state.session.familyId);
  if (!family) {
    return;
  }

  const latestByRoom = getLatestMessageByRoom(family);
  const previousByRoom = state.lastMessageByRoom ?? {};

  for (const room of getRoomsForMember(family, state.session.memberId)) {
    if (room.mutedBy?.[state.session.memberId]) {
      continue;
    }

    const latestMessage = latestByRoom[room.id];
    if (!latestMessage || latestMessage.senderId === state.session.memberId) {
      continue;
    }

    if (previousByRoom[room.id]?.id === latestMessage.id) {
      continue;
    }

    await self.registration.showNotification(createRoomTitle(family, room, state.session.memberId), {
      body: createNotificationBody(latestMessage),
      icon: "./icons/icon-192.png",
      badge: "./icons/icon-192.png",
      tag: `${state.session.familyId}:${room.id}`,
      data: {
        familyId: state.session.familyId,
        roomId: room.id,
      },
    });
  }

  state.lastMessageByRoom = Object.fromEntries(
    Object.entries(latestByRoom).map(([roomId, message]) => [roomId, {
      id: message.id,
      createdAt: message.createdAt,
    }]),
  );
  await writeBackgroundState(state);
}

async function fetchFamilySnapshot(config, familyId) {
  const response = await fetch(`${config.url}/rest/v1/rpc/app_get_family_snapshot`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: config.anonKey,
      Authorization: `Bearer ${config.anonKey}`,
    },
    body: JSON.stringify({
      p_family_id: familyId,
    }),
  });

  if (!response.ok) {
    return null;
  }

  return response.json();
}

function getLatestMessageByRoom(family) {
  return (family.messages ?? []).reduce((accumulator, message) => {
    const previous = accumulator[message.roomId];
    if (!previous || previous.createdAt.localeCompare(message.createdAt) <= 0) {
      accumulator[message.roomId] = message;
    }
    return accumulator;
  }, {});
}

function getRoomsForMember(family, memberId) {
  return (family.rooms ?? []).filter((room) => room.memberIds?.includes(memberId));
}

function createRoomTitle(family, room, currentMemberId) {
  if (room.type === "family") {
    return family.name || "가족 채팅";
  }

  if (room.type === "dm") {
    const peerId = (room.memberIds ?? []).find((memberId) => memberId !== currentMemberId);
    const peer = (family.members ?? []).find((member) => member.id === peerId);
    return peer?.name || "가족 1:1";
  }

  return room.title || "가족 채팅";
}

function createNotificationBody(message) {
  if (message.type === "image" && message.text) {
    return `사진 · ${message.text}`;
  }

  if (message.type === "image") {
    return "새 사진이 도착했습니다.";
  }

  return message.text || "새 메시지가 도착했습니다.";
}
