import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const STORAGE_KEY = "familychat.closed.pwa.v2";
const CHANNEL_KEY = "familychat.closed.pwa.channel";
const MAX_IMAGE_SIZE = 2 * 1024 * 1024;
const REALTIME_TABLES = ["families", "members", "rooms", "room_members", "invites", "messages", "message_reads"];
const ACTIVE_REFRESH_INTERVAL_MS = 3000;
const BACKGROUND_REFRESH_INTERVAL_MS = 12000;

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
  familyPresenceLabel: document.getElementById("familyPresenceLabel"),
  roomList: document.getElementById("roomList"),
  memberList: document.getElementById("memberList"),
  inviteSection: document.getElementById("inviteSection"),
  inviteList: document.getElementById("inviteList"),
  createInviteButton: document.getElementById("createInviteButton"),
  drawer: document.getElementById("drawer"),
  drawerScrim: document.getElementById("drawerScrim"),
  openDrawerButton: document.getElementById("openDrawerButton"),
  closeDrawerButton: document.getElementById("closeDrawerButton"),
  roomTypeLabel: document.getElementById("roomTypeLabel"),
  roomTitleLabel: document.getElementById("roomTitleLabel"),
  muteToggleButton: document.getElementById("muteToggleButton"),
  chatMeta: document.getElementById("chatMeta"),
  messageList: document.getElementById("messageList"),
  composerForm: document.getElementById("composerForm"),
  messageInput: document.getElementById("messageInput"),
  imageInput: document.getElementById("imageInput"),
  imagePreviewWrap: document.getElementById("imagePreviewWrap"),
  imagePreview: document.getElementById("imagePreview"),
  removeImageButton: document.getElementById("removeImageButton"),
  installButton: document.getElementById("installButton"),
  notificationButton: document.getElementById("notificationButton"),
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

bootstrap();

async function bootstrap() {
  normalizeState();
  registerEvents();
  registerServiceWorker();

  if (!hasSupabaseConfig) {
    render();
    showToast("supabase.config.js에 Supabase URL과 anon key를 입력하세요.");
    return;
  }

  await refreshCurrentFamily({ skipToast: true });
  render();
  syncLiveRefresh();
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
    familyName: profile.familyName ?? "가족",
    memberName: profile.memberName ?? "사용자",
    role: profile.role ?? "member",
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
        state.families = [];
        state.currentSession = null;
        removeDeviceProfile(sessionAtStart.familyId, sessionAtStart.memberId);
        unsubscribeFamilyChanges();
        stopLiveRefresh();
        if (persist) {
          saveState();
        }
        if (!skipToast) {
          showToast("가족 세션을 찾을 수 없습니다.");
        }
        return null;
      }

      normalizeFamily(family);
      state.families = [family];

      const member = findMember(family, sessionAtStart.memberId);
      if (!member) {
        state.currentSession = null;
        removeDeviceProfile(sessionAtStart.familyId, sessionAtStart.memberId);
        unsubscribeFamilyChanges();
        stopLiveRefresh();
        if (persist) {
          saveState();
        }
        if (!skipToast) {
          showToast("저장된 프로필을 더 이상 사용할 수 없습니다.");
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
      });

      subscribeToFamilyChanges(family.id);
      syncLiveRefresh();

      if (persist) {
        saveState({ broadcast: false });
      }

      if (notify) {
        maybeNotify(priorState, state);
      }

      return family;
    } catch (error) {
      console.error("Supabase sync failed", error);
      if (!skipToast) {
        showToast(extractErrorMessage(error, "Supabase 동기화에 실패했습니다."));
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
    return "가족 전체방";
  }

  if (room.type === "dm") {
    return getDirectPeer(family, room, memberId)?.name ?? "1:1 채팅";
  }

  return room.title || "가족 그룹방";
}

function createRoomSubtitle(family, room, memberId) {
  if (room.type === "family") {
    return `${family.members.length}명 참여 중`;
  }

  if (room.type === "dm") {
    const peer = getDirectPeer(family, room, memberId);
    return peer ? formatPresence(peer.lastSeenAt) : "가족 내부 1:1";
  }

  return "가족 내부 소규모 그룹";
}

function getRoomPreview(family, room) {
  const message = getMessagesForRoom(family, room.id).at(-1);
  if (!message) {
    return "아직 메시지가 없습니다.";
  }
  if (message.type === "system") {
    return message.text;
  }
  if (message.type === "image" && message.text) {
    return `사진 · ${message.text}`;
  }
  if (message.type === "image") {
    return "사진";
  }
  return message.text;
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
  elements.imageInput.addEventListener("change", handleImageSelection);
  elements.removeImageButton.addEventListener("click", clearPendingImage);
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

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    deferredInstallPrompt = event;
    renderInstallButton();
  });

  window.addEventListener("appinstalled", () => {
    deferredInstallPrompt = null;
    renderInstallButton();
    showToast("홈 화면에 앱 아이콘이 추가되었습니다.");
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
    showToast("가족 이름과 관리자 이름을 입력하세요.");
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
    });
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    elements.createFamilyForm.reset();
    render();
    showToast("가족 그룹이 만들어졌습니다.");
    broadcastRefresh();
  } catch (error) {
    console.error("Create family failed", error);
    showToast(extractErrorMessage(error, "가족 그룹 생성에 실패했습니다."));
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
    showToast("초대 코드와 이름을 입력하세요.");
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
    });
    saveState();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    elements.joinFamilyForm.reset();
    render();
    showToast(`${session.familyName} 가족에 참여했습니다.`);
    broadcastRefresh();
  } catch (error) {
    console.error("Join family failed", error);
    showToast(extractErrorMessage(error, "가족 참여에 실패했습니다."));
  }
}

async function handleCreateInvite() {
  const family = getCurrentFamily();
  const member = getCurrentMember();

  if (!family || !member || member.role !== "admin") {
    showToast("관리자만 초대 코드를 만들 수 있습니다.");
    return;
  }

  try {
    const invite = await createInviteRemote(family.id, member.id);
    await refreshCurrentFamily({ persist: false, skipToast: true });
    render();
    showToast(`${invite.code} 생성 완료`);
    broadcastRefresh();
  } catch (error) {
    console.error("Create invite failed", error);
    showToast(extractErrorMessage(error, "초대 코드 생성에 실패했습니다."));
  }
}

function handleInviteClick(event) {
  const button = event.target.closest("[data-copy-invite]");
  if (!button) {
    return;
  }

  const code = button.dataset.copyInvite;
  navigator.clipboard?.writeText(code).then(
    () => showToast("초대 코드를 복사했습니다."),
    () => showToast("복사에 실패했습니다."),
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

  const button = event.target.closest("[data-member-id]");
  const family = getCurrentFamily();
  const currentMember = getCurrentMember();

  if (!button || !family || !currentMember) {
    return;
  }

  const targetId = button.dataset.memberId;
  if (targetId === currentMember.id) {
    showToast("현재 사용자입니다.");
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
    showToast(extractErrorMessage(error, "1:1 채팅방을 열지 못했습니다."));
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

  const profile = getSavedProfile(button.dataset.profileKey);
  if (!profile) {
    showToast("저장된 프로필을 찾을 수 없습니다.");
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
    showToast("저장된 프로필을 더 이상 사용할 수 없습니다.");
    return;
  }

  render();
  await touchCurrentMember();
  await markActiveRoomRead({ silent: true });
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

  if (!family || !member || !room) {
    return;
  }

  if (!text && !pendingImage) {
    showToast("메시지나 사진을 넣어 주세요.");
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
    await touchCurrentMember();
    await refreshCurrentFamily({ persist: false, skipToast: true });
    render();
    await markActiveRoomRead({ silent: true });
    broadcastRefresh();
  } catch (error) {
    console.error("Send message failed", error);
    showToast(extractErrorMessage(error, "메시지 전송에 실패했습니다."));
  }
}

function handleImageSelection(event) {
  const file = event.target.files?.[0];
  if (!file) {
    return;
  }

  if (!file.type.startsWith("image/")) {
    showToast("이미지 파일만 보낼 수 있습니다.");
    event.target.value = "";
    return;
  }

  if (file.size > MAX_IMAGE_SIZE) {
    showToast("이미지는 2MB 이하만 허용합니다.");
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
  state.currentSession = null;
  state.families = [];
  unsubscribeFamilyChanges();
  stopLiveRefresh();
  saveState();
  render();
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
      showToast(extractErrorMessage(error, "읽음 상태를 저장하지 못했습니다."));
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
    showToast(extractErrorMessage(error, "알림 설정 저장에 실패했습니다."));
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
  elements.currentRoleLabel.textContent = member.role === "admin" ? "관리자" : "일반 사용자";
  elements.currentMemberLabel.textContent = member.name;
  elements.familyPresenceLabel.textContent = `${family.members.length}명 가족 그룹 · 가족 외 연결 차단`;
  elements.inviteSection.classList.toggle("hidden", member.role !== "admin");

  renderRoomList(family, member, rooms);
  renderMemberList(family, member);
  renderInviteList(family, member);
  renderChat(family, member, activeRoom);
  renderInstallButton();
}

function renderSavedProfiles() {
  const profiles = state.deviceProfiles.map((profile) => ({
    key: `${profile.familyId}:${profile.memberId}`,
    familyName: profile.familyName,
    memberName: profile.memberName,
    role: profile.role,
  }));

  elements.savedProfilesPanel.classList.toggle("hidden", profiles.length === 0);

  const markup = profiles.length
    ? profiles.map((profile) => `
      <button class="saved-profile" type="button" data-profile-key="${profile.key}">
        <div>
          <strong>${escapeHtml(profile.memberName)}</strong>
          <p>${escapeHtml(profile.familyName)} · ${profile.role === "admin" ? "관리자" : "일반 사용자"}</p>
        </div>
        <span class="status-chip">입장</span>
      </button>
    `).join("")
    : `<p class="room-meta">이 기기에 저장된 프로필이 없습니다.</p>`;

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

    return `
      <button class="room-card ${active ? "active" : ""}" type="button" data-room-id="${room.id}">
        <div class="room-head">
          <div class="room-main">
            <div class="room-avatar" style="background:${avatarColor(title)}">${escapeHtml(title.slice(0, 1))}</div>
            <div>
              <strong class="room-title">${escapeHtml(title)}</strong>
              <p class="room-meta">${escapeHtml(subtitle)}</p>
            </div>
          </div>
          ${unread ? `<span class="unread-badge">${unread}</span>` : muted ? `<span class="room-badge">무음</span>` : ""}
        </div>
        <p class="room-preview">${escapeHtml(preview)}</p>
      </button>
    `;
  }).join("");
}

function renderMemberList(family, currentMember) {
  elements.memberList.innerHTML = family.members.map((member) => `
    <button class="member-card" type="button" data-member-id="${member.id}">
      <div class="member-avatar" style="background:${avatarColor(member.name)}">${escapeHtml(member.name.slice(0, 1))}</div>
      <div>
        <strong>${escapeHtml(member.name)}${member.id === currentMember.id ? " (나)" : ""}</strong>
        <p class="room-meta">${member.role === "admin" ? "관리자" : "일반 사용자"} · ${escapeHtml(formatPresence(member.lastSeenAt))}</p>
      </div>
    </button>
  `).join("");
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
        <p>사용 가능 · ${formatDateTime(invite.createdAt)}</p>
        <div class="message-card-footer">
          <span class="status-chip">사용 가능</span>
          <button class="ghost-button compact" type="button" data-copy-invite="${invite.code}">복사</button>
        </div>
      </article>
    `).join("")
    : `<p class="room-meta">아직 초대 코드가 없습니다.</p>`;
}

function renderChat(family, member, room) {
  if (!room) {
    elements.roomTypeLabel.textContent = "채팅방 없음";
    elements.roomTitleLabel.textContent = "가족 참여를 기다리는 중";
    elements.chatMeta.innerHTML = "";
    elements.messageList.innerHTML = `<div class="empty-state">가족 구성원이 참여하면 대화를 시작할 수 있습니다.</div>`;
    return;
  }

  const messages = getMessagesForRoom(family, room.id);

  elements.roomTypeLabel.textContent = room.type === "family" ? "가족 전체방" : room.type === "dm" ? "가족 내부 1:1" : "가족 그룹방";
  elements.roomTitleLabel.textContent = createRoomTitle(family, room, member.id);
  elements.muteToggleButton.textContent = room.mutedBy?.[member.id] ? "알림 꺼짐" : "알림 켜짐";

  if (room.type === "family") {
    elements.chatMeta.innerHTML = `
      <p>${family.members.map((item) => item.name).join(" · ")}</p>
      <p>가족 외 사용자와는 연결되지 않습니다.</p>
    `;
  } else {
    const peer = getDirectPeer(family, room, member.id);
    elements.chatMeta.innerHTML = `
      <p>${peer ? `${peer.name}님과의 가족 내부 1:1` : "가족 내부 1:1"}</p>
      <p>${peer ? formatPresence(peer.lastSeenAt) : ""}</p>
    `;
  }

  elements.messageList.innerHTML = messages.length
    ? messages.map((message) => renderMessage(family, member, room, message)).join("")
    : `<div class="empty-state">첫 메시지를 보내 가족 대화를 시작하세요.</div>`;

  elements.messageList.scrollTop = elements.messageList.scrollHeight;
}

function renderMessage(family, currentMember, room, message) {
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

  return `
    <div class="message-row ${isSelf ? "self" : ""}">
      ${isSelf ? "" : `<div class="avatar" style="background:${avatarColor(sender?.name || "가족")}">${escapeHtml((sender?.name || "?").slice(0, 1))}</div>`}
      <article class="message-card">
        ${isSelf ? "" : `<p class="message-author">${escapeHtml(sender?.name || "알 수 없음")}</p>`}
        ${message.text ? `<p>${escapeHtml(message.text)}</p>` : ""}
        ${message.imageDataUrl ? `<img class="message-image" src="${message.imageDataUrl}" alt="보낸 이미지">` : ""}
        <div class="message-card-footer">
          <span>${formatTime(message.createdAt)}</span>
          <span>${room.type === "family" ? `읽음 ${readCount}/${Math.max(family.members.length - 1, 0)}` : readCount ? "읽음" : "전달됨"}</span>
        </div>
      </article>
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
}

function upsertDeviceProfile(profile) {
  const existing = state.deviceProfiles.find((item) => item.familyId === profile.familyId && item.memberId === profile.memberId);
  if (existing) {
    existing.familyName = profile.familyName;
    existing.memberName = profile.memberName;
    existing.role = profile.role;
    existing.savedAt = new Date().toISOString();
    return;
  }

  state.deviceProfiles.push({
    familyId: profile.familyId,
    memberId: profile.memberId,
    familyName: profile.familyName,
    memberName: profile.memberName,
    role: profile.role,
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

function autoResizeComposer() {
  elements.messageInput.style.height = "auto";
  elements.messageInput.style.height = `${Math.min(elements.messageInput.scrollHeight, 140)}px`;
}

function renderInstallButton() {
  if (isStandaloneMode()) {
    elements.installButton.disabled = true;
    elements.installButton.textContent = "설치 완료";
    return;
  }

  elements.installButton.disabled = false;
  elements.installButton.textContent = deferredInstallPrompt ? "앱 설치" : "홈 화면 추가";
}

async function promptInstall() {
  if (isStandaloneMode()) {
    showToast("이미 홈 화면에서 바로 실행할 수 있습니다.");
    return;
  }

  if (!deferredInstallPrompt) {
    showToast(getInstallHelpMessage());
    return;
  }

  deferredInstallPrompt.prompt();
  const choice = await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  renderInstallButton();
  if (choice.outcome !== "accepted") {
    showToast("앱 설치를 취소했습니다.");
  }
}

async function requestNotificationPermission() {
  if (!("Notification" in window)) {
    showToast("이 브라우저는 알림을 지원하지 않습니다.");
    return;
  }

  const result = await Notification.requestPermission();
  showToast(result === "granted" ? "알림 권한이 허용되었습니다." : "알림 권한이 허용되지 않았습니다.");
}

function maybeNotify(previousState, nextState) {
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

  getRoomsForMember(family, session.memberId).forEach((room) => {
    if (room.mutedBy?.[session.memberId]) {
      return;
    }

    const nextLast = family.messages.filter((message) => message.roomId === room.id).at(-1);
    const prevLast = previousFamily?.messages.filter((message) => message.roomId === room.id).at(-1);
    if (!nextLast || nextLast.id === prevLast?.id || nextLast.senderId === session.memberId) {
      return;
    }

    new Notification(createRoomTitle(family, room, session.memberId), {
      body: nextLast.type === "image" ? "새 사진이 도착했습니다." : nextLast.text || "새 메시지가 도착했습니다.",
      icon: "icons/icon-192.png",
      badge: "icons/icon-192.png",
      tag: room.id,
    });
  });
}

function registerServiceWorker() {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("service-worker.js").catch((error) => {
      console.error("Service worker registration failed", error);
    });
  }
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
    return "최근 접속 정보 없음";
  }

  const diffMs = Date.now() - new Date(lastSeenAt).getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) {
    return "현재 활동 중";
  }
  if (minutes < 60) {
    return `${minutes}분 전 활동`;
  }

  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours}시간 전 접속`;
  }

  const days = Math.floor(hours / 24);
  return `${days}일 전 접속`;
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

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.classList.remove("hidden");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    elements.toast.classList.add("hidden");
  }, 2200);
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

  showToast("supabase.config.js에 Supabase URL과 anon key를 입력하세요.");
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
    return "Safari의 공유 버튼에서 '홈 화면에 추가'를 선택하세요.";
  }

  if (/Android/i.test(userAgent)) {
    return "브라우저 메뉴에서 '앱 설치' 또는 '홈 화면에 추가'를 선택하세요.";
  }

  return "브라우저 메뉴에서 '앱 설치' 또는 '홈 화면에 추가'를 선택하세요.";
}
