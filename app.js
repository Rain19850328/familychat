import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const STORAGE_KEY = "familychat.closed.pwa.v2";
const CHANNEL_KEY = "familychat.closed.pwa.channel";
const MAX_IMAGE_SIZE = 2 * 1024 * 1024;
const MAX_PROFILE_IMAGE_SIZE = 1024 * 1024;
const REALTIME_TABLES = ["families", "members", "rooms", "room_members", "invites", "messages", "message_reads"];
const ACTIVE_REFRESH_INTERVAL_MS = 3000;
const BACKGROUND_REFRESH_INTERVAL_MS = 12000;
const BACKGROUND_SYNC_TAG = "familychat-message-check";
const PUSH_FUNCTION_PATH = "/functions/v1/push-notifications";
const PRESET_AVATARS = [
  { key: "adult-man", label: "어른 남자", src: "avatars/adult-man.svg" },
  { key: "adult-woman", label: "어른 여자", src: "avatars/adult-woman.svg" },
  { key: "boy", label: "아이 남자", src: "avatars/boy.svg" },
  { key: "girl", label: "아이 여자", src: "avatars/girl.svg" },
  { key: "sparkle-friend", label: "반짝 친구", src: "avatars/sparkle-friend.svg" },
];

const elements = {
  onboardingView: document.getElementById("onboardingView"),
  appView: document.getElementById("appView"),
  savedProfilesPanel: document.getElementById("savedProfilesPanel"),
  savedProfilesList: document.getElementById("savedProfilesList"),
  appProfileList: document.getElementById("appProfileList"),
  createFamilyForm: document.getElementById("createFamilyForm"),
  joinFamilyForm: document.getElementById("joinFamilyForm"),
  familyNameInput: document.getElementById("familyNameInput"),
  adminNameInput: document.getElementById("adminNameInput"),
  inviteCodeInput: document.getElementById("inviteCodeInput"),
  memberNameInput: document.getElementById("memberNameInput"),
  familyNameLabel: document.getElementById("familyNameLabel"),
  currentRoleLabel: document.getElementById("currentRoleLabel"),
  currentMemberLabel: document.getElementById("currentMemberLabel"),
  currentMemberAvatarBadge: document.getElementById("currentMemberAvatarBadge"),
  familyPresenceLabel: document.getElementById("familyPresenceLabel"),
  roomList: document.getElementById("roomList"),
  memberList: document.getElementById("memberList"),
  inviteSection: document.getElementById("inviteSection"),
  inviteList: document.getElementById("inviteList"),
  createInviteButton: document.getElementById("createInviteButton"),
  openProfileButton: document.getElementById("openProfileButton"),
  profileSummaryAvatar: document.getElementById("profileSummaryAvatar"),
  profileSummaryName: document.getElementById("profileSummaryName"),
  profileForm: document.getElementById("profileForm"),
  profileNameInput: document.getElementById("profileNameInput"),
  profileAvatarPreview: document.getElementById("profileAvatarPreview"),
  profileAvatarFileInput: document.getElementById("profileAvatarFileInput"),
  profileAvatarUploadButton: document.getElementById("profileAvatarUploadButton"),
  profileAvatarResetButton: document.getElementById("profileAvatarResetButton"),
  avatarPresetGrid: document.getElementById("avatarPresetGrid"),
  profileModal: document.getElementById("profileModal"),
  profileModalScrim: document.getElementById("profileModalScrim"),
  closeProfileModalButton: document.getElementById("closeProfileModalButton"),
  drawer: document.getElementById("drawer"),
  drawerScrim: document.getElementById("drawerScrim"),
  openDrawerButton: document.getElementById("openDrawerButton"),
  closeDrawerButton: document.getElementById("closeDrawerButton"),
  roomTitleLabel: document.getElementById("roomTitleLabel"),
  muteToggleButton: document.getElementById("muteToggleButton"),
  messageList: document.getElementById("messageList"),
  composerForm: document.getElementById("composerForm"),
  messageInput: document.getElementById("messageInput"),
  sendMessageButton: document.getElementById("sendMessageButton"),
  imageInput: document.getElementById("imageInput"),
  imagePreviewWrap: document.getElementById("imagePreviewWrap"),
  imagePreview: document.getElementById("imagePreview"),
  removeImageButton: document.getElementById("removeImageButton"),
  installButton: document.getElementById("installButton"),
  notificationButton: document.getElementById("notificationButton"),
  pushStatusNote: document.getElementById("pushStatusNote"),
  logoutButton: document.getElementById("logoutButton"),
  offlineBanner: document.getElementById("offlineBanner"),
  toast: document.getElementById("toast"),
};

const syncChannel = "BroadcastChannel" in window ? new BroadcastChannel(CHANNEL_KEY) : null;
const supabaseConfig = window.__SUPABASE_CONFIG__ ?? {};
const hasSupabaseConfig = isSupabaseConfigured(supabaseConfig);
const supabase = hasSupabaseConfig
  ? createClient(supabaseConfig.url, supabaseConfig.anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  })
  : null;

let state = loadState();
let pendingImage = null;
let deferredInstallPrompt = null;
let toastTimer = null;
let familyChannel = null;
let subscribedFamilyId = null;
let refreshPromise = null;
let refreshTimer = null;
let scheduledRefreshPromise = null;
let queuedFamilyRefresh = false;
let serviceWorkerRegistrationPromise = null;
let profileDraftMemberId = null;
let profileDraft = null;
let profileModalOpen = false;
let composerStabilizeFrame = 0;
let pushSyncPromise = null;
let lastPushSyncKey = "";
let pushDiagnostics = createPushDiagnostics();

bootstrap();

async function bootstrap() {
  normalizeState();
  registerEvents();
  registerServiceWorker();
  syncViewportInset();

  if (!hasSupabaseConfig) {
    render();
    showToast("supabase.config.js??Supabase URL??anon key????낆젾??뤾쉭??");
    return;
  }

  await refreshCurrentFamily({ skipToast: true });
  render();
  syncLiveRefresh();
  void syncServiceWorkerState();
  void syncPushSubscription();
  void markActiveRoomRead({ silent: true });
}

function createEmptyState() {
  return {
    version: 2,
    families: [],
    deviceProfiles: [],
    currentSession: null,
    meta: {
      lastUpdatedAt: Date.now(),
    },
  };
}

function loadState() {

  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return createEmptyState();
    }

    const parsed = JSON.parse(raw);
    return {
      ...createEmptyState(),
      deviceProfiles: Array.isArray(parsed.deviceProfiles) ? parsed.deviceProfiles : [],
      currentSession: parsed.currentSession && typeof parsed.currentSession === "object" ? parsed.currentSession : null,
      meta: parsed.meta && typeof parsed.meta === "object" ? parsed.meta : { lastUpdatedAt: Date.now() },
    };
  } catch (error) {
    console.error("State load failed", error);
    return createEmptyState();
  }
}

function normalizeState() {
  state.families = Array.isArray(state.families) ? state.families : [];
  state.deviceProfiles = Array.isArray(state.deviceProfiles) ? state.deviceProfiles : [];

  state.deviceProfiles = state.deviceProfiles.map((profile) => ({
    familyId: profile.familyId,
    memberId: profile.memberId,
    familyName: profile.familyName ?? "\uAC00\uC871",
    memberName: profile.memberName ?? "\uC0AC\uC6A9\uC790",
    role: profile.role ?? "member",
    avatarKey: profile.avatarKey ?? null,
    avatarImageDataUrl: profile.avatarImageDataUrl ?? null,
    savedAt: profile.savedAt ?? new Date().toISOString(),
  })).filter((profile) => profile.familyId && profile.memberId);

  state.families.forEach(normalizeFamily);
}

function normalizeFamily(family) {
  family.members = Array.isArray(family.members) ? family.members : [];
  family.rooms = Array.isArray(family.rooms) ? family.rooms : [];
  family.invites = Array.isArray(family.invites) ? family.invites : [];
  family.messages = Array.isArray(family.messages) ? family.messages : [];
  family.settings = family.settings || { allowGroupRooms: false };

  family.members.forEach((member) => {
    member.avatarKey = member.avatarKey ?? null;
    member.avatarImageDataUrl = member.avatarImageDataUrl ?? null;
  });

  family.rooms.forEach((room) => {
    room.memberIds = Array.isArray(room.memberIds) ? room.memberIds : [];
    room.mutedBy = room.mutedBy && typeof room.mutedBy === "object" ? room.mutedBy : {};
  });

  family.messages.forEach((message) => {
    message.readBy = message.readBy && typeof message.readBy === "object" ? message.readBy : {};
  });
}

function saveState({ broadcast = true } = {}) {
  state.meta.lastUpdatedAt = Date.now();
  const snapshot = {
    version: 2,
    deviceProfiles: state.deviceProfiles,
    currentSession: state.currentSession,
    meta: state.meta,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));

  if (broadcast && syncChannel) {
    syncChannel.postMessage({ type: "sync", at: state.meta.lastUpdatedAt });
  }

  void syncServiceWorkerState();
}

function broadcastRefresh() {
  if (syncChannel) {
    syncChannel.postMessage({ type: "refresh", at: Date.now() });
  }
}

async function syncState() {
  const previousState = structuredClone(state);
  const localState = loadState();

  state.deviceProfiles = localState.deviceProfiles;
  state.currentSession = localState.currentSession;
  state.meta = localState.meta;

  await refreshCurrentFamily({
    previousState,
    notify: true,
    persist: false,
    skipToast: true,
  });
  render();
}

async function refreshCurrentFamily({
  previousState = null,
  notify = false,
  persist = true,
  skipToast = false,
} = {}) {
  if (!supabase || !state.currentSession) {
    state.families = [];
    unsubscribeFamilyChanges();
    stopLiveRefresh();
    if (persist) {
      saveState({ broadcast: false });
    }
    return null;
  }

  if (refreshPromise) {
    return refreshPromise;
  }

  const priorState = previousState ?? structuredClone(state);
  const sessionAtStart = { ...state.currentSession };

  refreshPromise = (async () => {
    try {
      const family = await fetchFamilySnapshot(sessionAtStart.familyId);

      if (!state.currentSession
        || state.currentSession.familyId !== sessionAtStart.familyId
        || state.currentSession.memberId !== sessionAtStart.memberId) {
        return null;
      }

      if (!family) {
        void clearPushSubscription(sessionAtStart.memberId);
        lastPushSyncKey = "";
        state.families = [];
        state.currentSession = null;
        removeDeviceProfile(sessionAtStart.familyId, sessionAtStart.memberId);
        unsubscribeFamilyChanges();
        stopLiveRefresh();
        if (persist) {
          saveState();
        }
        if (!skipToast) {
          showToast("\uAC00\uC871 \uC138\uC158\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.");
        }
        return null;
      }

      normalizeFamily(family);
      state.families = [family];

      const member = findMember(family, sessionAtStart.memberId);
      if (!member) {
        void clearPushSubscription(sessionAtStart.memberId);
        lastPushSyncKey = "";
        state.currentSession = null;
        removeDeviceProfile(sessionAtStart.familyId, sessionAtStart.memberId);
        unsubscribeFamilyChanges();
        stopLiveRefresh();
        if (persist) {
          saveState();
        }
        if (!skipToast) {
          showToast("???貫留??袁⑥쨮?袁⑹뱽 ????곴맒 ?????????곷뮸??덈뼄.");
        }
        return null;
      }

      const rooms = getRoomsForMember(family, member.id);
      state.currentSession.activeRoomId = rooms.find((room) => room.id === sessionAtStart.activeRoomId)?.id ?? rooms[0]?.id ?? null;

      upsertDeviceProfile({
        familyId: family.id,
        memberId: member.id,
        familyName: family.name,
        memberName: member.name,
        role: member.role,
        avatarKey: member.avatarKey,
        avatarImageDataUrl: member.avatarImageDataUrl,
      });

      subscribeToFamilyChanges(family.id);
      syncLiveRefresh();

      if (persist) {
        saveState({ broadcast: false });
      }

      void syncServiceWorkerState();
      void syncPushSubscription();

      if (notify) {
        void maybeNotify(priorState, state);
      }

      return family;
    } catch (error) {
      console.error("Supabase sync failed", error);
      if (!skipToast) {
        showToast(extractErrorMessage(error, "Supabase ??녿┛?遺용퓠 ??쎈솭??됰뮸??덈뼄."));
      }
      return null;
    } finally {
      refreshPromise = null;
    }
  })();

  return refreshPromise;
}

function subscribeToFamilyChanges(familyId) {
  if (!supabase || subscribedFamilyId === familyId) {
    return;
  }

  unsubscribeFamilyChanges();

  let channel = supabase.channel(`family-sync:${familyId}`);
  channel = channel.on("postgres_changes", {
    event: "*",
    schema: "public",
    table: "families",
    filter: `id=eq.${familyId}`,
  }, () => {
    void scheduleFamilyRefresh();
  });

  REALTIME_TABLES
    .filter((table) => table !== "families")
    .forEach((table) => {
      channel = channel.on("postgres_changes", {
        event: "*",
        schema: "public",
        table,
        filter: `family_id=eq.${familyId}`,
      }, () => {
        void scheduleFamilyRefresh();
      });
    });

  familyChannel = channel.subscribe((status) => {
    if (status === "SUBSCRIBED") {
      void scheduleFamilyRefresh();
    }

    if (status === "CHANNEL_ERROR") {
      console.error("Realtime subscription failed");
      queueLiveRefresh(1200);
    }

    if (status === "TIMED_OUT" || status === "CLOSED") {
      queueLiveRefresh(1200);
    }
  });
  subscribedFamilyId = familyId;
}

function unsubscribeFamilyChanges() {
  if (supabase && familyChannel) {
    supabase.removeChannel(familyChannel);
  }

  familyChannel = null;
  subscribedFamilyId = null;
}

async function scheduleFamilyRefresh() {
  queuedFamilyRefresh = true;

  if (scheduledRefreshPromise) {
    return scheduledRefreshPromise;
  }

  scheduledRefreshPromise = (async () => {
    try {
      while (queuedFamilyRefresh) {
        queuedFamilyRefresh = false;

        const previousState = structuredClone(state);
        await refreshCurrentFamily({
          previousState,
          notify: true,
          persist: false,
          skipToast: true,
        });
        render();
        syncLiveRefresh();
      }
    } finally {
      scheduledRefreshPromise = null;
    }
  })();

  return scheduledRefreshPromise;
}

function syncLiveRefresh() {
  if (!hasSupabaseConfig || !state.currentSession || !navigator.onLine) {
    stopLiveRefresh();
    return;
  }

  queueLiveRefresh();
}

function queueLiveRefresh(delay = getLiveRefreshInterval()) {
  window.clearTimeout(refreshTimer);

  if (!hasSupabaseConfig || !state.currentSession || !navigator.onLine) {
    refreshTimer = null;
    return;
  }

  refreshTimer = window.setTimeout(async () => {
    await scheduleFamilyRefresh();
    queueLiveRefresh();
  }, delay);
}

function stopLiveRefresh() {
  window.clearTimeout(refreshTimer);
  refreshTimer = null;
}

function getLiveRefreshInterval() {
  return document.visibilityState === "visible"
    ? ACTIVE_REFRESH_INTERVAL_MS
    : BACKGROUND_REFRESH_INTERVAL_MS;
}

async function rpc(name, params = {}) {
  const { data, error } = await supabase.rpc(name, params);
  if (error) {
    throw error;
  }
  return data;
}

async function fetchFamilySnapshot(familyId) {
  return rpc("app_get_family_snapshot", {
    p_family_id: familyId,
  });
}

async function createFamilyRemote(familyName, adminName) {
  return rpc("app_create_family", {
    p_family_name: familyName,
    p_admin_name: adminName,
  });
}

async function joinFamilyRemote(inviteCode, memberName) {
  return rpc("app_join_family", {
    p_invite_code: inviteCode,
    p_member_name: memberName,
  });
}

async function createInviteRemote(familyId, memberId) {
  return rpc("app_create_invite", {
    p_family_id: familyId,
    p_admin_member_id: memberId,
  });
}

async function getOrCreateDmRoomRemote(familyId, memberId, targetId) {
  return rpc("app_get_or_create_dm_room", {
    p_family_id: familyId,
    p_first_member_id: memberId,
    p_second_member_id: targetId,
  });
}

async function sendMessageRemote(familyId, roomId, senderId, messageType, text, imageDataUrl) {
  return rpc("app_send_message", {
    p_family_id: familyId,
    p_room_id: roomId,
    p_sender_id: senderId,
    p_message_type: messageType,
    p_text: text,
    p_image_data_url: imageDataUrl,
  });
}

async function markRoomReadRemote(roomId, memberId) {
  return rpc("app_mark_room_read", {
    p_room_id: roomId,
    p_member_id: memberId,
  });
}

async function setRoomMuteRemote(roomId, memberId, muted) {
  return rpc("app_set_room_mute", {
    p_room_id: roomId,
    p_member_id: memberId,
    p_muted: muted,
  });
}

async function touchMemberRemote(memberId) {
  return rpc("app_touch_member", {
    p_member_id: memberId,
  });
}

async function updateMemberProfileRemote(memberId, name, avatarKey, avatarImageDataUrl) {
  return rpc("app_update_member_profile", {
    p_member_id: memberId,
    p_name: name,
    p_avatar_key: avatarKey ?? "",
    p_avatar_image_data_url: avatarImageDataUrl ?? "",
  });
}

async function removeMemberRemote(familyId, adminMemberId, targetMemberId) {
  return rpc("app_remove_member", {
    p_family_id: familyId,
    p_admin_member_id: adminMemberId,
    p_target_member_id: targetMemberId,
  });
}

async function upsertPushSubscriptionRemote(memberId, endpoint, p256dh, auth, userAgent) {
  return rpc("app_upsert_push_subscription", {
    p_member_id: memberId,
    p_endpoint: endpoint,
    p_p256dh: p256dh,
    p_auth: auth,
    p_user_agent: userAgent ?? "",
  });
}

async function removePushSubscriptionRemote(memberId, endpoint = null) {
  return rpc("app_remove_push_subscription", {
    p_member_id: memberId,
    p_endpoint: endpoint ?? null,
  });
}

function findFamily(familyId) {
  return state.families.find((family) => family.id === familyId);
}

function findMember(family, memberId) {
  return family.members.find((member) => member.id === memberId);
}

function findRoom(family, roomId) {
  return family.rooms.find((room) => room.id === roomId);
}

function getCurrentFamily() {
  return state.currentSession ? findFamily(state.currentSession.familyId) : null;
}

function getCurrentMember() {
  const family = getCurrentFamily();
  return family && state.currentSession ? findMember(family, state.currentSession.memberId) : null;
}

function getActiveRoom() {
  const family = getCurrentFamily();
  return family && state.currentSession ? findRoom(family, state.currentSession.activeRoomId) : null;
}

function getMessagesForRoom(family, roomId) {
  return family.messages
    .filter((message) => message.roomId === roomId)
    .sort((left, right) => left.createdAt.localeCompare(right.createdAt));
}

function getRoomsForMember(family, memberId) {
  return family.rooms
    .filter((room) => room.memberIds.includes(memberId))
    .sort((left, right) => {
      if (left.type === "family" && right.type !== "family") {
        return -1;
      }
      if (right.type === "family" && left.type !== "family") {
        return 1;
      }

      const leftAt = getMessagesForRoom(family, left.id).at(-1)?.createdAt ?? left.createdAt;
      const rightAt = getMessagesForRoom(family, right.id).at(-1)?.createdAt ?? right.createdAt;
      return rightAt.localeCompare(leftAt);
    });
}

function getUnreadCount(family, room, memberId) {
  return getMessagesForRoom(family, room.id).filter((message) => {
    if (message.type === "system" || message.senderId === memberId) {
      return false;
    }
    return !message.readBy?.[memberId];
  }).length;
}

function getDirectPeer(family, room, memberId) {
  return room.memberIds
    .filter((candidate) => candidate !== memberId)
    .map((candidate) => findMember(family, candidate))
    .find(Boolean);
}

function createRoomTitle(family, room, memberId) {
  if (room.type === "family") {
    return "\uAC00\uC871 \uC804\uCCB4\uBC29";
  }

  if (room.type === "dm") {
    return getDirectPeer(family, room, memberId)?.name ?? "1:1 \uCC44\uD305";
  }

  return room.title || "\uAC00\uC871 \uADF8\uB8F9\uBC29";
}

function createRoomSubtitle(family, room, memberId) {
  if (room.type === "family") {
    return `${family.members.length}\uBA85 \uCC38\uC5EC \uC911`;
  }

  if (room.type === "dm") {
    const peer = getDirectPeer(family, room, memberId);
    return peer ? formatPresence(peer.lastSeenAt) : "\uAC00\uC871 \uC678\uBD80 1:1";
  }

  return "\uAC00\uC871 \uADF8\uB8F9";
}

function getRoomPreview(family, room) {
  const message = getMessagesForRoom(family, room.id).at(-1);
  if (!message) {
    return "\uC544\uC9C1 \uBA54\uC2DC\uC9C0\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.";
  }
  if (message.type === "system") {
    return message.text;
  }
  if (message.type === "image" && message.text) {
    return `\uC0AC\uC9C4 \u00B7 ${message.text}`;
  }
  if (message.type === "image") {
    return "\uC0AC\uC9C4";
  }
  return message.text;
}

function renderRoomAvatarMarkup(family, room, memberId, title) {
  if (room.type === "dm") {
    const peer = getDirectPeer(family, room, memberId);
    if (peer) {
      return renderAvatarMarkup(peer, "room-avatar");
    }
  }

  return `<div class="room-avatar room-avatar-family" style="background:${avatarColor(title)}">${escapeHtml(title.slice(0, 1))}</div>`;
}

function registerEvents() {
  elements.createFamilyForm.addEventListener("submit", (event) => {
    void handleCreateFamily(event);
  });
  elements.joinFamilyForm.addEventListener("submit", (event) => {
    void handleJoinFamily(event);
  });
  elements.roomList.addEventListener("click", (event) => {
    void handleRoomClick(event);
  });
  elements.memberList.addEventListener("click", (event) => {
    void handleMemberClick(event);
  });
  elements.savedProfilesList.addEventListener("click", (event) => {
    void handleProfileClick(event);
  });
  elements.appProfileList.addEventListener("click", (event) => {
    void handleProfileClick(event);
  });
  elements.inviteList.addEventListener("click", handleInviteClick);
  elements.createInviteButton.addEventListener("click", () => {
    void handleCreateInvite();
  });
  elements.composerForm.addEventListener("submit", (event) => {
    void handleSendMessage(event);
  });
  elements.sendMessageButton.addEventListener("pointerdown", handleComposerSubmitPointerDown);
  elements.imageInput.addEventListener("change", handleImageSelection);
  elements.removeImageButton.addEventListener("click", clearPendingImage);
  elements.openProfileButton.addEventListener("click", openProfileModal);
  elements.profileForm.addEventListener("submit", (event) => {
    void handleProfileSubmit(event);
  });
  elements.profileNameInput.addEventListener("input", handleProfileNameInput);
  elements.profileAvatarUploadButton.addEventListener("click", () => {
    elements.profileAvatarFileInput.click();
  });
  elements.profileAvatarFileInput.addEventListener("change", handleProfileAvatarSelection);
  elements.profileAvatarResetButton.addEventListener("click", handleProfileAvatarReset);
  elements.avatarPresetGrid.addEventListener("click", handleAvatarPresetClick);
  elements.profileModalScrim.addEventListener("click", () => setProfileModal(false));
  elements.closeProfileModalButton.addEventListener("click", () => setProfileModal(false));
  elements.openDrawerButton.addEventListener("click", () => setDrawer(true));
  elements.closeDrawerButton.addEventListener("click", () => setDrawer(false));
  elements.drawerScrim.addEventListener("click", () => setDrawer(false));
  elements.logoutButton.addEventListener("click", handleLogout);
  elements.muteToggleButton.addEventListener("click", () => {
    void toggleMuteRoom();
  });
  elements.installButton.addEventListener("click", promptInstall);
  elements.notificationButton.addEventListener("click", () => {
    void requestNotificationPermission();
  });
  elements.messageInput.addEventListener("input", autoResizeComposer);
  elements.messageInput.addEventListener("focus", () => {
    ensureComposerVisible();
  });

  window.addEventListener("storage", (event) => {
    if (event.key === STORAGE_KEY) {
      void syncState();
    }
  });

  if (syncChannel) {
    syncChannel.addEventListener("message", () => {
      void syncState();
    });
  }

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.addEventListener("message", (event) => {
      if (event.data?.type === "PUSH_SUBSCRIPTION_UPDATED") {
        void refreshPushDiagnostics();
      }
    });
  }

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    deferredInstallPrompt = event;
    renderInstallButton();
  });

  window.addEventListener("appinstalled", () => {
    deferredInstallPrompt = null;
    renderInstallButton();
    showToast("\uD648 \uD654\uBA74\uC5D0 \uC571 \uC544\uC774\uCF58\uC774 \uCD94\uAC00\uB418\uC5C8\uC2B5\uB2C8\uB2E4.");
  });

  window.addEventListener("online", () => {
    renderOfflineState();
    if (hasSupabaseConfig) {
      void scheduleFamilyRefresh();
      queueLiveRefresh(1200);
    }
  });
  window.addEventListener("offline", () => {
    renderOfflineState();
    stopLiveRefresh();
  });

  document.addEventListener("visibilitychange", () => {
    syncLiveRefresh();

    if (document.visibilityState !== "visible") {
      return;
    }

    void touchCurrentMember();
    void scheduleFamilyRefresh();
    void markActiveRoomRead({ silent: true });
  });

  window.addEventListener("pageshow", () => {
    if (!hasSupabaseConfig) {
      return;
    }

    void scheduleFamilyRefresh();
    queueLiveRefresh(1000);
    void syncServiceWorkerState();
    void refreshPushDiagnostics();
  });

  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", handleViewportChange);
    window.visualViewport.addEventListener("scroll", handleViewportChange);
  } else {
    window.addEventListener("resize", handleViewportChange);
  }

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && profileModalOpen) {
      setProfileModal(false);
    }
  });
}

async function handleCreateFamily(event) {
  event.preventDefault();
  if (!ensureBackendReady()) {
    return;
  }

  const familyName = elements.familyNameInput.value.trim();
  const adminName = elements.adminNameInput.value.trim();

  if (!familyName || !adminName) {
    showToast("\uAC00\uC871 \uC774\uB984\uACFC \uAD00\uB9AC\uC790 \uC774\uB984\uC744 \uC785\uB825\uD558\uC138\uC694.");
    return;
  }

  try {
    const session = await createFamilyRemote(familyName, adminName);
    state.currentSession = {
      familyId: session.familyId,
      memberId: session.memberId,
      activeRoomId: session.activeRoomId,
    };
    upsertDeviceProfile({
      familyId: session.familyId,
      memberId: session.memberId,
      familyName: session.familyName,
      memberName: session.memberName,
      role: session.role,
      avatarKey: session.avatarKey ?? null,
      avatarImageDataUrl: session.avatarImageDataUrl ?? null,
    });
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    elements.createFamilyForm.reset();
    render();
    await syncPushSubscription({ force: true });
    showToast("\uAC00\uC871 \uADF8\uB8F9\uC774 \uB9CC\uB4E4\uC5B4\uC84C\uC2B5\uB2C8\uB2E4.");
    broadcastRefresh();
  } catch (error) {
    console.error("Create family failed", error);
    showToast(extractErrorMessage(error, "\uAC00\uC871 \uADF8\uB8F9 \uC0DD\uC131\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

async function handleJoinFamily(event) {
  event.preventDefault();
  if (!ensureBackendReady()) {
    return;
  }

  const inviteCode = elements.inviteCodeInput.value.trim().toUpperCase();
  const memberName = elements.memberNameInput.value.trim();

  if (!inviteCode || !memberName) {
    showToast("\uCD08\uB300 \uCF54\uB4DC\uC640 \uC774\uB984\uC744 \uC785\uB825\uD558\uC138\uC694.");
    return;
  }

  try {
    const session = await joinFamilyRemote(inviteCode, memberName);
    state.currentSession = {
      familyId: session.familyId,
      memberId: session.memberId,
      activeRoomId: session.activeRoomId,
    };
    upsertDeviceProfile({
      familyId: session.familyId,
      memberId: session.memberId,
      familyName: session.familyName,
      memberName: session.memberName,
      role: session.role,
      avatarKey: session.avatarKey ?? null,
      avatarImageDataUrl: session.avatarImageDataUrl ?? null,
    });
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    elements.joinFamilyForm.reset();
    render();
    await syncPushSubscription({ force: true });
    showToast(`${session.familyName} \uAC00\uC871\uC5D0 \uCC38\uC5EC\uD588\uC2B5\uB2C8\uB2E4.`);
    broadcastRefresh();
  } catch (error) {
    console.error("Join family failed", error);
    showToast(extractErrorMessage(error, "\uAC00\uC871 \uCC38\uC5EC\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

async function handleCreateInvite() {
  const family = getCurrentFamily();
  const member = getCurrentMember();

  if (!family || !member || member.role !== "admin") {
    showToast("\uAD00\uB9AC\uC790\uB9CC \uCD08\uB300 \uCF54\uB4DC\uB97C \uB9CC\uB4E4 \uC218 \uC788\uC2B5\uB2C8\uB2E4.");
    return;
  }

  try {
    const invite = await createInviteRemote(family.id, member.id);
    await refreshCurrentFamily({ persist: false, skipToast: true });
    render();
    showToast(`${invite.code} \uC0DD\uC131 \uC644\uB8CC`);
    broadcastRefresh();
  } catch (error) {
    console.error("Create invite failed", error);
    showToast(extractErrorMessage(error, "\uCD08\uB300 \uCF54\uB4DC \uC0DD\uC131\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

function handleInviteClick(event) {
  const button = event.target.closest("[data-copy-invite]");
  if (!button) {
    return;
  }

  const code = button.dataset.copyInvite;
  navigator.clipboard?.writeText(code).then(
    () => showToast("\uCD08\uB300 \uCF54\uB4DC\uB97C \uBCF5\uC0AC\uD588\uC2B5\uB2C8\uB2E4."),
    () => showToast("\uBCF5\uC0AC\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."),
  );
}

async function handleRoomClick(event) {
  const button = event.target.closest("[data-room-id]");
  if (!button || !state.currentSession) {
    return;
  }

  state.currentSession.activeRoomId = button.dataset.roomId;
  saveState();
  render();
  setDrawer(false);
  await markActiveRoomRead({ silent: true });
}

async function handleMemberClick(event) {
  if (!ensureBackendReady()) {
    return;
  }

  const family = getCurrentFamily();
  const currentMember = getCurrentMember();

  if (!family || !currentMember) {
    return;
  }

  const removeButton = event.target.closest("[data-remove-member]");
  if (removeButton) {
    await handleRemoveMember(removeButton.dataset.removeMember);
    return;
  }

  const chatButton = event.target.closest("[data-open-dm-member]");
  if (!chatButton) {
    return;
  }

  const targetId = chatButton.dataset.openDmMember;
  if (targetId === currentMember.id) {
    showToast("\uD604\uC7AC \uC0AC\uC6A9\uC790\uC785\uB2C8\uB2E4.");
    return;
  }

  try {
    const room = await getOrCreateDmRoomRemote(family.id, currentMember.id, targetId);
    state.currentSession.activeRoomId = room.id;
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    render();
    setDrawer(false);
    await markActiveRoomRead({ silent: true });
    broadcastRefresh();
  } catch (error) {
    console.error("Open dm failed", error);
    showToast(extractErrorMessage(error, "1:1 \uCC44\uD305\uBC29\uC744 \uC5F4\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

async function handleRemoveMember(targetId) {
  const family = getCurrentFamily();
  const currentMember = getCurrentMember();
  const targetMember = family ? findMember(family, targetId) : null;

  if (!family || !currentMember || currentMember.role !== "admin" || !targetMember) {
    showToast("\uAD00\uB9AC\uC790\uB9CC \uAC00\uC871 \uAD6C\uC131\uC6D0\uC744 \uD0C8\uD1F4\uC2DC\uD0AC \uC218 \uC788\uC2B5\uB2C8\uB2E4.");
    return;
  }

  if (targetMember.id === currentMember.id) {
    showToast("\uBC29\uC7A5 \uC790\uC2E0\uC740 \uD0C8\uD1F4 \uCC98\uB9AC\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.");
    return;
  }

  if (targetMember.role === "admin") {
    showToast("\uBC29\uC7A5\uC740 \uAC15\uD1F4 \uB300\uC0C1\uC774 \uC544\uB2D9\uB2C8\uB2E4.");
    return;
  }

  const confirmed = window.confirm(`${targetMember.name}\uB2D8\uC744 \uAC00\uC871\uC5D0\uC11C \uD0C8\uD1F4\uC2DC\uD0AC\uAE4C\uC694?`);
  if (!confirmed) {
    return;
  }

  try {
    await removeMemberRemote(family.id, currentMember.id, targetMember.id);
    removeDeviceProfile(family.id, targetMember.id);
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    render();
    broadcastRefresh();
    showToast(`${targetMember.name}\uB2D8\uC744 \uD0C8\uD1F4\uCC98\uB9AC\uD588\uC2B5\uB2C8\uB2E4.`);
  } catch (error) {
    console.error("Remove member failed", error);
    showToast(extractErrorMessage(error, "\uAD6C\uC131\uC6D0 \uD0C8\uD1F4 \uCC98\uB9AC\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

async function handleProfileClick(event) {
  if (!ensureBackendReady()) {
    return;
  }

  const button = event.target.closest("[data-profile-key]");
  if (!button) {
    return;
  }

  setProfileModal(false);

  const profile = getSavedProfile(button.dataset.profileKey);
  if (!profile) {
    showToast("\uC800\uC7A5\uB41C \uD504\uB85C\uD544\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.");
    return;
  }

  state.currentSession = {
    familyId: profile.familyId,
    memberId: profile.memberId,
    activeRoomId: null,
  };
  saveState();

  const family = await refreshCurrentFamily({ persist: false, skipToast: true });
  if (!family) {
    render();
    showToast("\uC800\uC7A5\uB41C \uD504\uB85C\uD544\uC744 \uB354 \uC774\uC0C1 \uC0AC\uC6A9\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.");
    return;
  }

  render();
  await touchCurrentMember();
  await markActiveRoomRead({ silent: true });
}

function openProfileModal() {
  const member = getCurrentMember();
  if (!member) {
    return;
  }

  syncProfileDraft(member);
  renderProfileEditor(member);
  if (window.innerWidth < 900) {
    setDrawer(false);
  }
  setProfileModal(true);
}

function handleProfileNameInput(event) {
  const member = getCurrentMember();
  if (!member) {
    return;
  }

  syncProfileDraft(member);
  profileDraft.name = event.target.value;
}

function handleAvatarPresetClick(event) {
  const button = event.target.closest("[data-avatar-key]");
  const member = getCurrentMember();
  if (!button || !member) {
    return;
  }

  syncProfileDraft(member);
  profileDraft.avatarKey = button.dataset.avatarKey;
  profileDraft.avatarImageDataUrl = null;
  elements.profileAvatarFileInput.value = "";
  renderProfileEditor(member);
}

function handleProfileAvatarReset() {
  const member = getCurrentMember();
  if (!member) {
    return;
  }

  syncProfileDraft(member);
  profileDraft.avatarKey = null;
  profileDraft.avatarImageDataUrl = null;
  elements.profileAvatarFileInput.value = "";
  renderProfileEditor(member);
}

function handleProfileAvatarSelection(event) {
  const file = event.target.files?.[0];
  const member = getCurrentMember();
  if (!file || !member) {
    return;
  }

  if (!file.type.startsWith("image/")) {
    showToast("프로필 사진은 이미지 파일만 사용할 수 있어요.");
    event.target.value = "";
    return;
  }

  if (file.size > MAX_PROFILE_IMAGE_SIZE) {
    showToast("프로필 사진은 1MB 이하로 올려 주세요.");
    event.target.value = "";
    return;
  }

  const reader = new FileReader();
  reader.onload = () => {
    syncProfileDraft(member);
    profileDraft.avatarKey = null;
    profileDraft.avatarImageDataUrl = reader.result;
    renderProfileEditor(member);
  };
  reader.readAsDataURL(file);
}

async function handleProfileSubmit(event) {
  event.preventDefault();
  if (!ensureBackendReady()) {
    return;
  }

  const family = getCurrentFamily();
  const member = getCurrentMember();
  if (!family || !member) {
    return;
  }

  syncProfileDraft(member);
  const nextName = profileDraft.name.trim();
  if (!nextName) {
    showToast("이름을 입력해 주세요.");
    return;
  }

  try {
    const updatedMember = await updateMemberProfileRemote(
      member.id,
      nextName,
      profileDraft.avatarKey,
      profileDraft.avatarImageDataUrl,
    );

    upsertDeviceProfile({
      familyId: family.id,
      memberId: member.id,
      familyName: family.name,
      memberName: updatedMember.name,
      role: updatedMember.role,
      avatarKey: updatedMember.avatarKey,
      avatarImageDataUrl: updatedMember.avatarImageDataUrl,
    });
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    profileDraftMemberId = null;
    profileDraft = null;
    setProfileModal(false, { resetDraft: false });
    render();
    broadcastRefresh();
    showToast("프로필을 저장했어요.");
  } catch (error) {
    console.error("Update profile failed", error);
    showToast(extractErrorMessage(error, "프로필 저장에 실패했습니다."));
  }
}

async function handleSendMessage(event) {
  event.preventDefault();
  if (!ensureBackendReady()) {
    return;
  }

  const family = getCurrentFamily();
  const member = getCurrentMember();
  const room = getActiveRoom();
  const text = elements.messageInput.value.trim();
  const shouldKeepComposerFocused = document.activeElement === elements.messageInput;

  if (!family || !member || !room) {
    return;
  }

  if (!text && !pendingImage) {
    showToast("\uBA54\uC2DC\uC9C0\uB098 \uC0AC\uC9C4\uC744 \uC801\uC5B4 \uC8FC\uC138\uC694.");
    return;
  }


  try {
    await sendMessageRemote(
      family.id,
      room.id,
      member.id,
      pendingImage ? "image" : "text",
      text,
      pendingImage?.dataUrl ?? "",
    );

    elements.messageInput.value = "";
    clearPendingImage();
    autoResizeComposer();
    if (shouldKeepComposerFocused) {
      focusComposer();
    }
    await touchCurrentMember();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    render();
    if (shouldKeepComposerFocused) {
      focusComposer();
    }
    await markActiveRoomRead({ silent: true });
    broadcastRefresh();
  } catch (error) {
    console.error("Send message failed", error);
    showToast(extractErrorMessage(error, "\uBA54\uC2DC\uC9C0 \uC804\uC1A1\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

function handleImageSelection(event) {
  const file = event.target.files?.[0];
  if (!file) {
    return;
  }

  if (!file.type.startsWith("image/")) {
    showToast("\uC774\uBBF8\uC9C0 \uD30C\uC77C\uB9CC \uBCF4\uB0BC \uC218 \uC788\uC2B5\uB2C8\uB2E4.");
    event.target.value = "";
    return;
  }

  if (file.size > MAX_IMAGE_SIZE) {
    showToast("\uC774\uBBF8\uC9C0\uB294 2MB \uC774\uD558\uB9CC \uD5C8\uC6A9\uB429\uB2C8\uB2E4.");
    event.target.value = "";
    return;
  }

  const reader = new FileReader();
  reader.onload = () => {
    pendingImage = {
      name: file.name,
      dataUrl: reader.result,
    };
    renderPendingImage();
    event.target.value = "";
  };
  reader.readAsDataURL(file);
}

function handleLogout() {
  const memberId = state.currentSession?.memberId ?? null;
  void clearPushSubscription(memberId);
  lastPushSyncKey = "";
  setProfileModal(false);
  state.currentSession = null;
  state.families = [];
  unsubscribeFamilyChanges();
  stopLiveRefresh();
  saveState();
  render();
  void syncServiceWorkerState();
}

async function markActiveRoomRead({ silent = false } = {}) {
  const family = getCurrentFamily();
  const member = getCurrentMember();
  const room = getActiveRoom();

  if (!family || !member || !room) {
    return;
  }

  const changed = markRoomReadInState(family, room.id, member.id);
  if (!changed) {
    return;
  }

  render();

  try {
    await markRoomReadRemote(room.id, member.id);
    broadcastRefresh();
  } catch (error) {
    console.error("Mark room read failed", error);
    if (!silent) {
      showToast(extractErrorMessage(error, "\uC77D\uC74C \uC0C1\uD0DC\uB97C \uC800\uC7A5\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4."));
    }
  }
}

function markRoomReadInState(family, roomId, memberId) {
  let changed = false;

  getMessagesForRoom(family, roomId).forEach((message) => {
    if (message.type === "system") {
      return;
    }

    message.readBy = message.readBy || {};
    if (!message.readBy[memberId]) {
      message.readBy[memberId] = new Date().toISOString();
      changed = true;
    }
  });

  return changed;
}

async function toggleMuteRoom() {
  const room = getActiveRoom();
  const member = getCurrentMember();

  if (!room || !member) {
    return;
  }

  const nextMuted = !Boolean(room.mutedBy?.[member.id]);
  room.mutedBy = room.mutedBy || {};
  room.mutedBy[member.id] = nextMuted;
  render();

  try {
    await setRoomMuteRemote(room.id, member.id, nextMuted);
    broadcastRefresh();
  } catch (error) {
    console.error("Mute toggle failed", error);
    room.mutedBy[member.id] = !nextMuted;
    render();
    showToast(extractErrorMessage(error, "\uC54C\uB9BC \uC124\uC815 \uC800\uC7A5\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."));
  }
}

async function touchCurrentMember() {
  const family = getCurrentFamily();
  const member = getCurrentMember();

  if (!family || !member) {
    return;
  }

  member.lastSeenAt = new Date().toISOString();
  render();

  try {
    await touchMemberRemote(member.id);
  } catch (error) {
    console.error("Touch member failed", error);
  }
}

function render() {
  const family = getCurrentFamily();
  const member = getCurrentMember();

  renderOfflineState();
  renderSavedProfiles();
  renderBackendDisabledState();

  if (!family || !member) {
    syncProfileDraft(null);
    setProfileModal(false);
    elements.onboardingView.classList.remove("hidden");
    elements.appView.classList.add("hidden");
    setDrawer(false);
    return;
  }

  elements.onboardingView.classList.add("hidden");
  elements.appView.classList.remove("hidden");

  const rooms = getRoomsForMember(family, member.id);
  const activeRoom = rooms.find((room) => room.id === state.currentSession.activeRoomId) ?? rooms[0] ?? null;
  if (activeRoom && activeRoom.id !== state.currentSession.activeRoomId) {
    state.currentSession.activeRoomId = activeRoom.id;
    saveState({ broadcast: false });
  }

  elements.familyNameLabel.textContent = family.name;
  elements.currentRoleLabel.textContent = member.role === "admin" ? "\uAD00\uB9AC\uC790" : "\uC77C\uBC18 \uC0AC\uC6A9\uC790";
  elements.currentMemberLabel.textContent = member.name;
  elements.familyPresenceLabel.textContent = `${family.members.length}\uBA85 \uAC00\uC871 \uADF8\uB8F9 \u00B7 \uAC00\uC871 \uC678 \uC5F0\uACB0 \uCC28\uB2E8`;
  elements.inviteSection.classList.toggle("hidden", member.role !== "admin");
  setAvatarElement(elements.currentMemberAvatarBadge, member);

  renderProfileSummary(member);
  renderProfileEditor(member);
  renderRoomList(family, member, rooms);
  renderMemberList(family, member);
  renderInviteList(family, member);
  renderChat(family, member, activeRoom);
  renderInstallButton();
  renderPushStatus();
  void refreshPushDiagnostics();
}

function renderProfileSummary(member) {
  setAvatarElement(elements.profileSummaryAvatar, member);
  elements.profileSummaryName.textContent = member.name;
}

function renderSavedProfiles() {
  const profiles = state.deviceProfiles.map((profile) => ({
    key: `${profile.familyId}:${profile.memberId}`,
    familyName: profile.familyName,
    memberName: profile.memberName,
    role: profile.role,
    avatarKey: profile.avatarKey,
    avatarImageDataUrl: profile.avatarImageDataUrl,
  }));

  elements.savedProfilesPanel.classList.toggle("hidden", profiles.length === 0);

  const markup = profiles.length
    ? profiles.map((profile) => `
      <button class="saved-profile" type="button" data-profile-key="${profile.key}">
        ${renderAvatarMarkup(profile, "saved-profile-avatar")}
        <div>
          <strong>${escapeHtml(profile.memberName)}</strong>
          <p>${escapeHtml(profile.familyName)} \u00B7 ${profile.role === "admin" ? "\uAD00\uB9AC\uC790" : "\uC77C\uBC18 \uC0AC\uC6A9\uC790"}</p>
        </div>
        <span class="status-chip">\uC785\uC7A5</span>
      </button>
    `).join("")
    : `<p class="room-meta">\uC774 \uAE30\uAE30\uC5D0 \uC800\uC7A5\uB41C \uD504\uB85C\uD544\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.</p>`;

  elements.savedProfilesList.innerHTML = markup;
  elements.appProfileList.innerHTML = markup;
}

function renderRoomList(family, member, rooms) {
  elements.roomList.innerHTML = rooms.map((room) => {
    const active = state.currentSession.activeRoomId === room.id;
    const unread = getUnreadCount(family, room, member.id);
    const title = createRoomTitle(family, room, member.id);
    const subtitle = createRoomSubtitle(family, room, member.id);
    const preview = getRoomPreview(family, room);
    const muted = Boolean(room.mutedBy?.[member.id]);
    const typeLabel = room.type === "family" ? "\uAC00\uC871 \uC804\uCCB4\uBC29" : room.type === "dm" ? "1:1 \uB300\uD654" : "\uADF8\uB8F9 \uCC44\uD305";

    return `
      <button class="room-card room-card-${room.type} ${active ? "active" : ""}" type="button" data-room-id="${room.id}">
        <div class="room-head">
          <div class="room-main">
            ${renderRoomAvatarMarkup(family, room, member.id, title)}
            <div class="room-copy">
              <p class="room-kind">${typeLabel}</p>
              <strong class="room-title">${escapeHtml(title)}</strong>
              <p class="room-meta">${escapeHtml(subtitle)}</p>
            </div>
          </div>
          ${unread ? `<span class="unread-badge">${unread}</span>` : muted ? `<span class="room-badge">\uBB34\uC74C</span>` : ""}
        </div>
        <p class="room-preview">${escapeHtml(preview)}</p>
      </button>
    `;
  }).join("");
}

function renderMemberList(family, currentMember) {
  elements.memberList.innerHTML = family.members.map((member) => {
    const isSelf = member.id === currentMember.id;
    const canRemove = currentMember.role === "admin" && member.role !== "admin" && !isSelf;
    return `
      <article class="member-card ${isSelf ? "self" : ""}">
        <div class="member-card-main">
          ${renderAvatarMarkup(member, "member-avatar")}
          <div class="member-copy">
            <strong>${escapeHtml(member.name)}</strong>
          </div>
        </div>
        <div class="member-actions">
          ${isSelf ? `<span class="status-chip member-self-chip">\uB098</span>` : `<button class="ghost-button compact member-action-button" type="button" data-open-dm-member="${member.id}">\uB300\uD654</button>`}
          ${canRemove ? `<button class="secondary-button compact member-action-button member-remove-button" type="button" data-remove-member="${member.id}">\uD0C8\uD1F4</button>` : ""}
        </div>
      </article>
    `;
  }).join("");
}

function renderInviteList(family, member) {
  if (member.role !== "admin") {
    elements.inviteList.innerHTML = "";
    return;
  }

  const invites = [...family.invites]
    .filter((invite) => invite.status === "active")
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
    .slice(0, 1);
  elements.inviteList.innerHTML = invites.length
    ? invites.map((invite) => `
      <article class="invite-card">
        <strong class="invite-code">${invite.code}</strong>
        <p>\uC0AC\uC6A9 \uAC00\uB2A5 \u00B7 ${formatDateTime(invite.createdAt)}</p>
        <div class="message-card-footer">
          <span class="status-chip">\uC0AC\uC6A9 \uAC00\uB2A5</span>
          <button class="ghost-button compact" type="button" data-copy-invite="${invite.code}">\uBCF5\uC0AC</button>
        </div>
      </article>
    `).join("")
    : `<p class="room-meta">\uC544\uC9C1 \uCD08\uB300 \uCF54\uB4DC\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.</p>`;
}

function renderChat(family, member, room) {
  if (!room) {
    elements.roomTitleLabel.textContent = "\uAC00\uC871 \uCC38\uC5EC\uB97C \uAE30\uB2E4\uB9AC\uB294 \uC911";
    elements.messageList.innerHTML = `<div class="empty-state">\uAC00\uC871 \uAD6C\uC131\uC6D0\uC774 \uCC38\uC5EC\uD558\uBA74 \uB300\uD654\uAC00 \uC2DC\uC791\uB429\uB2C8\uB2E4.</div>`;
    return;
  }

  const messages = getMessagesForRoom(family, room.id);

  elements.roomTitleLabel.textContent = createRoomTitle(family, room, member.id);
  elements.muteToggleButton.textContent = room.mutedBy?.[member.id] ? "\uC54C\uB9BC \uAEBC\uC9D0" : "\uC54C\uB9BC \uCF1C\uC9D0";

  elements.messageList.innerHTML = messages.length
    ? messages.map((message, index) => renderMessage(
      family,
      member,
      room,
      message,
      messages[index - 1],
      messages[index + 1],
    )).join("")
    : `<div class="empty-state">\uCCAB \uBA54\uC2DC\uC9C0\uB97C \uBCF4\uB0B4 \uAC00\uC871 \uB300\uD654\uB97C \uC2DC\uC791\uD558\uC138\uC694.</div>`;

  elements.messageList.scrollTop = elements.messageList.scrollHeight;
}

function isSameMessageGroup(leftMessage, rightMessage) {
  if (!leftMessage || !rightMessage) {
    return false;
  }

  if (leftMessage.type === "system" || rightMessage.type === "system") {
    return false;
  }

  return leftMessage.senderId === rightMessage.senderId && formatTime(leftMessage.createdAt) === formatTime(rightMessage.createdAt);
}

function renderMessage(family, currentMember, room, message, previousMessage, nextMessage) {
  if (message.type === "system") {
    return `
      <div class="message-row system">
        <article class="message-card">
          <p>${escapeHtml(message.text)}</p>
          <div class="message-card-footer">
            <span>${formatTime(message.createdAt)}</span>
          </div>
        </article>
      </div>
    `;
  }

  const sender = findMember(family, message.senderId);
  const isSelf = message.senderId === currentMember.id;
  const readCount = Object.keys(message.readBy || {}).filter((memberId) => memberId !== currentMember.id).length;
  const isFirstInGroup = !isSameMessageGroup(previousMessage, message);
  const isLastInGroup = !isSameMessageGroup(message, nextMessage);
  const showAvatarColumn = !isSelf && room.type !== "dm";
  const showProfile = showAvatarColumn && isFirstInGroup;
  const showAuthor = showProfile;
  const timeLabel = formatTime(message.createdAt);
  const stateLabel = room.type === "family"
    ? `\uC77D\uC74C ${readCount}/${Math.max(family.members.length - 1, 0)}`
    : readCount ? "\uC77D\uC74C" : "\uBBF8\uC804\uB2EC";

  return `
    <div class="message-row ${isSelf ? "self" : ""} ${isFirstInGroup ? "" : "continued"}">
      ${showProfile ? renderAvatarMarkup(sender || { name: "?" }, "avatar") : ""}
      ${!showProfile && showAvatarColumn ? `<div class="avatar-spacer" aria-hidden="true"></div>` : ""}
      <div class="message-stack">
        ${showAuthor ? `<p class="message-author">${escapeHtml(sender?.name || "\uC774\uB984\uC5C6\uC74C")}</p>` : ""}
        <div class="message-bubble-group">
          ${isSelf && isLastInGroup ? `
            <div class="message-side-meta">
              ${stateLabel ? `<span>${escapeHtml(stateLabel)}</span>` : ""}
              <span>${timeLabel}</span>
            </div>
          ` : ""}
          <article class="message-card">
            ${message.text ? `<p>${escapeHtml(message.text)}</p>` : ""}
            ${message.imageDataUrl ? `<img class="message-image" src="${message.imageDataUrl}" alt="\uBCF4\uB0B8 \uC774\uBBF8\uC9C0">` : ""}
          </article>
          ${isSelf || !isLastInGroup ? "" : `
            <div class="message-side-meta">
              <span>${timeLabel}</span>
            </div>
          `}
        </div>
      </div>
    </div>
  `;
}

function renderPendingImage() {
  if (!pendingImage) {
    elements.imagePreviewWrap.classList.add("hidden");
    elements.imagePreview.removeAttribute("src");
    return;
  }

  elements.imagePreviewWrap.classList.remove("hidden");
  elements.imagePreview.src = pendingImage.dataUrl;
}

function clearPendingImage() {
  pendingImage = null;
  renderPendingImage();
}

function renderOfflineState() {
  elements.offlineBanner.classList.toggle("hidden", navigator.onLine);
}

function renderBackendDisabledState() {
  const disabled = !hasSupabaseConfig;
  [...elements.createFamilyForm.elements].forEach((field) => {
    field.disabled = disabled;
  });
  [...elements.joinFamilyForm.elements].forEach((field) => {
    field.disabled = disabled;
  });
  if (elements.profileForm) {
    [...elements.profileForm.elements].forEach((field) => {
      field.disabled = disabled;
    });
  }
  elements.openProfileButton.disabled = disabled;
}

function getPresetAvatarSrc(avatarKey) {
  return PRESET_AVATARS.find((item) => item.key === avatarKey)?.src ?? "";
}

function getAvatarUrl(profile) {
  return profile?.avatarImageDataUrl || getPresetAvatarSrc(profile?.avatarKey);
}

function getAvatarName(profile) {
  return profile?.name || profile?.memberName || "\uAC00\uC871";
}

function getAvatarInitial(profile) {
  return escapeHtml(getAvatarName(profile).slice(0, 1) || "?");
}

function renderAvatarMarkup(profile, className) {
  const avatarUrl = getAvatarUrl(profile);
  const avatarName = getAvatarName(profile);
  if (avatarUrl) {
    return `
      <div class="${className} has-avatar-image">
        <img class="avatar-photo" src="${escapeHtml(avatarUrl)}" alt="${escapeHtml(avatarName)}">
      </div>
    `;
  }

  return `
    <div class="${className}" style="background:${avatarColor(avatarName)}">
      ${getAvatarInitial(profile)}
    </div>
  `;
}

function setAvatarElement(element, profile) {
  if (!element) {
    return;
  }

  const avatarUrl = getAvatarUrl(profile);
  const avatarName = getAvatarName(profile);
  if (avatarUrl) {
    element.classList.add("has-avatar-image");
    element.style.background = "rgba(255, 255, 255, 0.96)";
    element.innerHTML = `<img class="avatar-photo" src="${escapeHtml(avatarUrl)}" alt="${escapeHtml(avatarName)}">`;
    return;
  }

  element.classList.remove("has-avatar-image");
  element.style.background = avatarColor(avatarName);
  element.textContent = avatarName.slice(0, 1) || "?";
}

function syncProfileDraft(member) {
  if (!member) {
    profileDraftMemberId = null;
    profileDraft = null;
    return;
  }

  if (profileDraftMemberId === member.id && profileDraft) {
    return;
  }

  profileDraftMemberId = member.id;
  profileDraft = {
    name: member.name,
    avatarKey: member.avatarKey ?? null,
    avatarImageDataUrl: member.avatarImageDataUrl ?? null,
  };
}

function createPushDiagnostics() {
  return {
    supported: supportsPushNotifications(),
    permission: "Notification" in window ? Notification.permission : "default",
    serviceWorkerReady: false,
    subscribed: false,
    standalone: isStandaloneMode(),
    error: "",
  };
}

function renderProfileEditor(member) {
  if (!member) {
    return;
  }

  syncProfileDraft(member);
  elements.profileNameInput.value = profileDraft.name;
  setAvatarElement(elements.profileAvatarPreview, {
    name: profileDraft.name || member.name,
    avatarKey: profileDraft.avatarKey,
    avatarImageDataUrl: profileDraft.avatarImageDataUrl,
  });

  const hasCustomAvatar = Boolean(profileDraft.avatarImageDataUrl);
  elements.avatarPresetGrid.innerHTML = PRESET_AVATARS.map((avatar) => {
    const selected = !hasCustomAvatar && profileDraft.avatarKey === avatar.key;
    return `
      <button
        class="avatar-preset ${selected ? "selected" : ""}"
        type="button"
        data-avatar-key="${avatar.key}"
        aria-pressed="${selected ? "true" : "false"}"
      >
        <img src="${avatar.src}" alt="${escapeHtml(avatar.label)}">
        <span>${escapeHtml(avatar.label)}</span>
      </button>
    `;
  }).join("");
}

function upsertDeviceProfile(profile) {
  const existing = state.deviceProfiles.find((item) => item.familyId === profile.familyId && item.memberId === profile.memberId);
  if (existing) {
    existing.familyName = profile.familyName;
    existing.memberName = profile.memberName;
    existing.role = profile.role;
    existing.avatarKey = profile.avatarKey ?? null;
    existing.avatarImageDataUrl = profile.avatarImageDataUrl ?? null;
    existing.savedAt = new Date().toISOString();
    return;
  }

  state.deviceProfiles.push({
    familyId: profile.familyId,
    memberId: profile.memberId,
    familyName: profile.familyName,
    memberName: profile.memberName,
    role: profile.role,
    avatarKey: profile.avatarKey ?? null,
    avatarImageDataUrl: profile.avatarImageDataUrl ?? null,
    savedAt: new Date().toISOString(),
  });
}

function removeDeviceProfile(familyId, memberId) {
  state.deviceProfiles = state.deviceProfiles.filter((profile) => !(profile.familyId === familyId && profile.memberId === memberId));
}

function getSavedProfile(profileKey) {
  const [familyId, memberId] = profileKey.split(":");
  return state.deviceProfiles.find((profile) => profile.familyId === familyId && profile.memberId === memberId) ?? null;
}

function setDrawer(open) {
  elements.drawer.classList.toggle("open", open);
  elements.drawerScrim.classList.toggle("hidden", !open || window.innerWidth >= 900);
}

function setProfileModal(open, { resetDraft = true } = {}) {
  profileModalOpen = open;
  elements.profileModal.classList.toggle("hidden", !open);
  document.body.classList.toggle("modal-open", open);

  if (open) {
    window.requestAnimationFrame(() => {
      elements.profileNameInput.focus({ preventScroll: true });
      elements.profileNameInput.select();
    });
  }

  if (!open) {
    elements.profileAvatarFileInput.value = "";
  }

  if (!open && resetDraft) {
    syncProfileDraft(null);
  }
}

function autoResizeComposer() {
  elements.messageInput.style.height = "auto";
  elements.messageInput.style.height = `${Math.min(elements.messageInput.scrollHeight, 140)}px`;
}

function handleComposerSubmitPointerDown(event) {
  event.preventDefault();
  focusComposer({ syncScroll: false });
}

function handleViewportChange() {
  syncViewportInset();
  if (document.activeElement === elements.messageInput) {
    ensureComposerVisible();
  }
}

function syncViewportInset() {
  const viewport = window.visualViewport;
  const keyboardOffset = viewport
    ? Math.max(0, window.innerHeight - (viewport.height + viewport.offsetTop))
    : 0;
  document.documentElement.style.setProperty("--keyboard-offset", `${Math.round(keyboardOffset)}px`);
}

function ensureComposerVisible() {
  window.cancelAnimationFrame(composerStabilizeFrame);
  composerStabilizeFrame = window.requestAnimationFrame(() => {
    elements.messageList.scrollTo({
      top: elements.messageList.scrollHeight,
      behavior: "auto",
    });
  });
}

function focusComposer({ syncScroll = true } = {}) {
  window.cancelAnimationFrame(composerStabilizeFrame);
  composerStabilizeFrame = window.requestAnimationFrame(() => {
    elements.messageInput.focus({ preventScroll: true });
    const length = elements.messageInput.value.length;
    if (typeof elements.messageInput.setSelectionRange === "function") {
      elements.messageInput.setSelectionRange(length, length);
    }
    if (syncScroll) {
      ensureComposerVisible();
    }
  });
}

function renderInstallButton() {
  if (isStandaloneMode()) {
    elements.installButton.disabled = true;
    elements.installButton.textContent = "\uC124\uCE58 \uC644\uB8CC";
    return;
  }

  elements.installButton.disabled = false;
  elements.installButton.textContent = "\uD648 \uD654\uBA74\uC5D0 \uCD94\uAC00";
}

function renderPushStatus() {
  if (!elements.pushStatusNote || !elements.notificationButton) {
    return;
  }

  const diagnostics = pushDiagnostics;
  const parts = [];

  if (!diagnostics.supported) {
    elements.notificationButton.disabled = true;
    elements.notificationButton.textContent = "\uD478\uC2DC \uBBF8\uC9C0\uC6D0";
    elements.pushStatusNote.textContent = "\uC774 \uBE0C\uB77C\uC6B0\uC800\uB294 Push API\uB97C \uC9C0\uC6D0\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.";
    return;
  }

  elements.notificationButton.disabled = false;
  elements.notificationButton.textContent = diagnostics.permission === "granted"
    ? "\uC54C\uB9BC \uAD8C\uD55C \uD655\uC778"
    : "\uC54C\uB9BC \uAD8C\uD55C \uC694\uCCAD";

  parts.push(diagnostics.permission === "granted"
    ? "\uAD8C\uD55C \uD5C8\uC6A9\uB428"
    : diagnostics.permission === "denied"
      ? "\uAD8C\uD55C \uCC28\uB2E8\uB428"
      : "\uAD8C\uD55C \uBBF8\uD5C8\uC6A9");
  parts.push(diagnostics.serviceWorkerReady
    ? "\uC11C\uBE44\uC2A4\uC6CC\uCEE4 \uC900\uBE44\uB428"
    : "\uC11C\uBE44\uC2A4\uC6CC\uCEE4 \uC900\uBE44 \uC911");
  parts.push(diagnostics.subscribed
    ? "\uD478\uC2DC \uAD6C\uB3C5 \uC5F0\uACB0\uB428"
    : "\uD478\uC2DC \uAD6C\uB3C5 \uC5C6\uC74C");

  if (!diagnostics.standalone) {
    parts.push("\uD648 \uD654\uBA74 \uCD94\uAC00 \uAD8C\uC7A5");
  }

  if (diagnostics.error) {
    parts.push(diagnostics.error);
  }

  elements.pushStatusNote.textContent = parts.join(" / ");
}

async function promptInstall() {
  if (isStandaloneMode()) {
    showToast("\uC774\uBBF8 \uD648 \uD654\uBA74\uC5D0\uC11C \uBC14\uB85C \uC2E4\uD589 \uC911\uC785\uB2C8\uB2E4.");
    return;
  }

  if (!deferredInstallPrompt) {
    showToast(getInstallHelpMessage(), 4200);
    return;
  }

  deferredInstallPrompt.prompt();
  const choice = await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  renderInstallButton();
  if (choice.outcome !== "accepted") {
    showToast("\uD648 \uD654\uBA74 \uCD94\uAC00\uB97C \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.");
  }
}

async function requestNotificationPermission() {
  if (!("Notification" in window)) {
    showToast("\uC774 \uBE0C\uB77C\uC6B0\uC800\uB294 \uC54C\uB9BC\uC744 \uC9C0\uC6D0\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.");
    return;
  }

  try {
    const result = await Notification.requestPermission();
    await syncServiceWorkerState();
    await syncPushSubscription({ force: true });
    await refreshPushDiagnostics();
    showToast(result === "granted" ? "\uC54C\uB9BC \uAD8C\uD55C\uC744 \uD5C8\uC6A9\uD588\uC2B5\uB2C8\uB2E4." : "\uC54C\uB9BC \uAD8C\uD55C\uC774 \uD5C8\uC6A9\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.");
  } catch (error) {
    console.error("Notification permission request failed", error);
    await refreshPushDiagnostics(`\uD478\uC2DC \uC5F0\uACB0 \uC2E4\uD328: ${extractErrorMessage(error, "\uAD6C\uB3C5 \uD655\uC778 \uD544\uC694")}`);
    showToast("\uC54C\uB9BC \uAD8C\uD55C \uBC0F \uD478\uC2DC \uC5F0\uACB0\uC744 \uD655\uC778\uD574\uC8FC\uC138\uC694.");
  }
}

async function maybeNotify(previousState, nextState) {
  if (!document.hidden || !("Notification" in window) || Notification.permission !== "granted") {
    return;
  }

  const session = nextState.currentSession;
  if (!session) {
    return;
  }

  const family = nextState.families.find((item) => item.id === session.familyId);
  const previousFamily = previousState.families.find((item) => item.id === session.familyId);
  if (!family) {
    return;
  }

  for (const room of getRoomsForMember(family, session.memberId)) {
    if (room.mutedBy?.[session.memberId]) {
      continue;
    }

    const nextLast = family.messages.filter((message) => message.roomId === room.id).at(-1);
    const prevLast = previousFamily?.messages.filter((message) => message.roomId === room.id).at(-1);
    if (!nextLast || nextLast.id === prevLast?.id || nextLast.senderId === session.memberId) {
      continue;
    }

    await showAppNotification(createRoomTitle(family, room, session.memberId), {
      body: nextLast.type === "image" ? "\uC0AC\uC9C4\uC774 \uB3C4\uCC29\uD588\uC2B5\uB2C8\uB2E4." : nextLast.text || "\uC0C8 \uBA54\uC2DC\uC9C0\uAC00 \uB3C4\uCC29\uD588\uC2B5\uB2C8\uB2E4.",
      tag: `${family.id}:${room.id}`,
      data: {
        roomId: room.id,
        familyId: family.id,
      },
    });
  }
}

function registerServiceWorker() {
  if ("serviceWorker" in navigator) {
    serviceWorkerRegistrationPromise = navigator.serviceWorker.register("service-worker.js").then(async (registration) => {
      await navigator.serviceWorker.ready;
      await configureBackgroundSync(registration);
      await refreshPushDiagnostics();
      return registration;
    }).catch((error) => {
      console.error("Service worker registration failed", error);
      void refreshPushDiagnostics("\uC11C\uBE44\uC2A4\uC6CC\uCEE4 \uB4F1\uB85D \uC2E4\uD328");
      return null;
    });
  }
}

async function configureBackgroundSync(registration) {
  if (!registration || !("Notification" in window) || Notification.permission !== "granted") {
    return;
  }

  if ("periodicSync" in registration) {
    try {
      await registration.periodicSync.register(BACKGROUND_SYNC_TAG, {
        minInterval: 60 * 1000,
      });
      return;
    } catch (error) {
      console.warn("Periodic background sync registration failed", error);
    }
  }

  if ("sync" in registration) {
    try {
      await registration.sync.register(BACKGROUND_SYNC_TAG);
    } catch (error) {
      console.warn("Background sync registration failed", error);
    }
  }
}

async function syncServiceWorkerState() {
  if (!("serviceWorker" in navigator) || !hasSupabaseConfig) {
    return;
  }

  const registration = await (serviceWorkerRegistrationPromise ?? navigator.serviceWorker.ready.catch(() => null));
  if (!registration) {
    return;
  }

  await configureBackgroundSync(registration);

  const worker = registration.active ?? registration.waiting ?? registration.installing;
  if (!worker) {
    return;
  }

  const family = getCurrentFamily();
  const session = state.currentSession;

  if (!session || !family) {
    worker.postMessage({ type: "CLEAR_SESSION" });
    return;
  }

  const lastMessageByRoom = {};
  family.messages.forEach((message) => {
    const previous = lastMessageByRoom[message.roomId];
    if (!previous || previous.createdAt.localeCompare(message.createdAt) <= 0) {
      lastMessageByRoom[message.roomId] = {
        id: message.id,
        createdAt: message.createdAt,
      };
    }
  });

  worker.postMessage({
    type: "SYNC_SESSION",
    payload: {
      config: {
        url: supabaseConfig.url,
        anonKey: supabaseConfig.anonKey,
      },
      session: {
        familyId: session.familyId,
        memberId: session.memberId,
      },
      lastMessageByRoom,
      notificationPermission: "Notification" in window ? Notification.permission : "default",
    },
  });
}

async function refreshPushDiagnostics(errorMessage = "") {
  pushDiagnostics = {
    supported: supportsPushNotifications(),
    permission: "Notification" in window ? Notification.permission : "default",
    serviceWorkerReady: false,
    subscribed: false,
    standalone: isStandaloneMode(),
    error: errorMessage,
  };

  if (!pushDiagnostics.supported) {
    renderPushStatus();
    return pushDiagnostics;
  }

  try {
    const registration = await (serviceWorkerRegistrationPromise ?? navigator.serviceWorker.ready.catch(() => null));
    pushDiagnostics.serviceWorkerReady = Boolean(registration);
    pushDiagnostics.subscribed = Boolean(await registration?.pushManager?.getSubscription?.());
  } catch (error) {
    pushDiagnostics.error = errorMessage || extractErrorMessage(error, "\uD478\uC2DC \uC0C1\uD0DC \uD655\uC778 \uC2E4\uD328");
  }

  renderPushStatus();
  return pushDiagnostics;
}

async function showAppNotification(title, options = {}) {
  const notificationOptions = {
    icon: "icons/icon-192.png",
    badge: "icons/icon-192.png",
    renotify: Boolean(options?.tag),
    ...options,
  };

  try {
    const registration = await (serviceWorkerRegistrationPromise ?? navigator.serviceWorker?.ready ?? Promise.resolve(null));
    if (registration?.showNotification) {
      await registration.showNotification(title, notificationOptions);
      return;
    }
  } catch (error) {
    console.warn("Service worker notification failed", error);
  }

  new Notification(title, notificationOptions);
}

function supportsPushNotifications() {
  return "serviceWorker" in navigator && "PushManager" in window;
}

async function fetchPushPublicKey() {
  const response = await fetch(`${supabaseConfig.url}${PUSH_FUNCTION_PATH}`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${supabaseConfig.anonKey}`,
      apikey: supabaseConfig.anonKey,
    },
  });

  if (!response.ok) {
    throw new Error("Failed to load push public key.");
  }

  const payload = await response.json();
  if (!payload?.publicKey) {
    throw new Error("Push public key is missing.");
  }

  return payload.publicKey;
}

async function syncPushSubscription({ force = false } = {}) {
  if (!hasSupabaseConfig || !supportsPushNotifications()) {
    return;
  }

  const session = state.currentSession;
  const permission = "Notification" in window ? Notification.permission : "default";
  const syncKey = session ? `${session.familyId}:${session.memberId}:${permission}` : `none:${permission}`;
  if (!force && syncKey === lastPushSyncKey) {
    return;
  }

  if (pushSyncPromise) {
    return pushSyncPromise;
  }

  pushSyncPromise = (async () => {
    const registration = await (serviceWorkerRegistrationPromise ?? navigator.serviceWorker.ready.catch(() => null));
    if (!registration?.pushManager) {
      return;
    }

    const existingSubscription = await registration.pushManager.getSubscription();

    if (!session || permission !== "granted") {
      if (session?.memberId) {
        await removePushSubscriptionRemote(session.memberId, existingSubscription?.endpoint ?? null);
      }
      await existingSubscription?.unsubscribe?.();
      lastPushSyncKey = syncKey;
      return;
    }

    const publicKey = await fetchPushPublicKey();
    const subscription = existingSubscription ?? await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(publicKey),
    });

    const serialized = subscription.toJSON();
    if (!serialized.endpoint || !serialized.keys?.p256dh || !serialized.keys?.auth) {
      throw new Error("Push subscription is incomplete.");
    }

    await upsertPushSubscriptionRemote(
      session.memberId,
      serialized.endpoint,
      serialized.keys.p256dh,
      serialized.keys.auth,
      navigator.userAgent ?? "",
    );
    lastPushSyncKey = syncKey;
  })().catch((error) => {
    console.error("Push subscription sync failed", error);
    void refreshPushDiagnostics(extractErrorMessage(error, "\uD478\uC2DC \uAD6C\uB3C5 \uC5F0\uACB0 \uC2E4\uD328"));
  }).finally(() => {
    pushSyncPromise = null;
    void refreshPushDiagnostics();
  });

  return pushSyncPromise;
}

async function clearPushSubscription(memberId) {
  if (!supportsPushNotifications()) {
    return;
  }

  try {
    const registration = await (serviceWorkerRegistrationPromise ?? navigator.serviceWorker.ready.catch(() => null));
    const subscription = await registration?.pushManager?.getSubscription?.();
    if (memberId) {
      await removePushSubscriptionRemote(memberId, subscription?.endpoint ?? null);
    }
    await subscription?.unsubscribe?.();
  } catch (error) {
    console.warn("Push subscription cleanup failed", error);
    void refreshPushDiagnostics(extractErrorMessage(error, "\uD478\uC2DC \uAD6C\uB3C5 \uC815\uB9AC \uC2E4\uD328"));
    return;
  }

  await refreshPushDiagnostics();
}

function urlBase64ToUint8Array(value) {
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  const base64 = (value + padding).replaceAll("-", "+").replaceAll("_", "/");
  const raw = atob(base64);
  return Uint8Array.from(raw, (character) => character.charCodeAt(0));
}

function formatTime(value) {
  return new Intl.DateTimeFormat("ko-KR", {
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function formatDateTime(value) {
  return new Intl.DateTimeFormat("ko-KR", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function formatPresence(lastSeenAt) {
  if (!lastSeenAt) {
    return "\uCD5C\uADFC \uC811\uC18D \uC815\uBCF4 \uC5C6\uC74C";
  }

  const diffMs = Date.now() - new Date(lastSeenAt).getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) {
    return "\uD604\uC7AC \uD65C\uB3D9 \uC911";
  }
  if (minutes < 60) {
    return `${minutes}\uBD84 \uC804 \uD65C\uB3D9`;
  }

  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours}\uC2DC\uAC04 \uC804 \uC811\uC18D`;
  }

  const days = Math.floor(hours / 24);
  return `${days}\uC77C \uC804 \uC811\uC18D`;
}

function avatarColor(value) {
  const palette = ["#f36b4f", "#217974", "#4f7cff", "#ff9e3d", "#7a5cff", "#ff6f91"];
  const total = value.split("").reduce((sum, character) => sum + character.charCodeAt(0), 0);
  return palette[total % palette.length];
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

function showToast(message, duration = 2200) {
  elements.toast.textContent = message;
  elements.toast.classList.remove("hidden");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    elements.toast.classList.add("hidden");
  }, duration);
}

function isSupabaseConfigured(config) {
  return Boolean(
    config.url
    && config.anonKey
    && !String(config.url).includes("YOUR_PROJECT_REF")
    && !String(config.anonKey).includes("YOUR_SUPABASE_ANON_KEY"),
  );
}

function ensureBackendReady() {
  if (supabase) {
    return true;
  }

  showToast("supabase.config.js\uC5D0 Supabase URL\uACFC anon key\uB97C \uC785\uB825\uD558\uC138\uC694.");
  return false;
}

function extractErrorMessage(error, fallbackMessage) {
  const message = error?.message?.trim();
  return message ? message : fallbackMessage;
}

function isStandaloneMode() {
  return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
}

function getInstallHelpMessage() {
  const userAgent = navigator.userAgent || "";
  const isIOS = /iPad|iPhone|iPod/.test(userAgent)
    || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

  if (isIOS) {
    return "Safari \uACF5\uC720 \uBC84\uD2BC\uC5D0\uC11C \"\uD648 \uD654\uBA74\uC5D0 \uCD94\uAC00\"\uB97C \uC120\uD0DD\uD558\uC138\uC694.";
  }

  if (/Android/i.test(userAgent)) {
    return "\uBE0C\uB77C\uC6B0\uC800 \uBA54\uB274\uC5D0\uC11C \"\uC124\uCE58\" \uB610\uB294 \"\uD648 \uD654\uBA74\uC5D0 \uCD94\uAC00\"\uB97C \uC120\uD0DD\uD558\uC138\uC694.";
  }

  return "\uBE0C\uB77C\uC6B0\uC800 \uBA54\uB274\uC5D0\uC11C \"\uC124\uCE58\" \uB610\uB294 \"\uD648 \uD654\uBA74\uC5D0 \uCD94\uAC00\"\uB97C \uC120\uD0DD\uD558\uC138\uC694.";
}

