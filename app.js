const STORAGE_KEY = "familychat.closed.pwa.v1";
const CHANNEL_KEY = "familychat.closed.pwa.channel";
const MAX_IMAGE_SIZE = 2 * 1024 * 1024;

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

let state = loadState();
let pendingImage = null;
let deferredInstallPrompt = null;
let toastTimer = null;

bootstrap();

function bootstrap() {
  normalizeState();
  ensureCurrentSession();
  registerEvents();
  registerServiceWorker();
  render();
}

function createEmptyState() {
  return {
    version: 1,
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
    return { ...createEmptyState(), ...JSON.parse(raw) };
  } catch (error) {
    console.error("State load failed", error);
    return createEmptyState();
  }
}

function normalizeState() {
  state.families = Array.isArray(state.families) ? state.families : [];
  state.deviceProfiles = Array.isArray(state.deviceProfiles) ? state.deviceProfiles : [];

  state.families.forEach((family) => {
    family.members = Array.isArray(family.members) ? family.members : [];
    family.rooms = Array.isArray(family.rooms) ? family.rooms : [];
    family.invites = Array.isArray(family.invites) ? family.invites : [];
    family.messages = Array.isArray(family.messages) ? family.messages : [];
    family.settings = family.settings || { allowGroupRooms: false };
  });
}

function saveState({ broadcast = true } = {}) {
  state.meta.lastUpdatedAt = Date.now();
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  if (broadcast && syncChannel) {
    syncChannel.postMessage({ type: "sync", at: state.meta.lastUpdatedAt });
  }
}

function syncState() {
  const previousState = structuredClone(state);
  state = loadState();
  normalizeState();
  ensureCurrentSession();
  maybeNotify(previousState, state);
  render();
}

function ensureCurrentSession() {
  if (!state.currentSession) {
    return;
  }

  const family = findFamily(state.currentSession.familyId);
  const member = family ? findMember(family, state.currentSession.memberId) : null;

  if (!family || !member) {
    state.currentSession = null;
    return;
  }

  touchMember(family.id, member.id);
  const rooms = getRoomsForMember(family, member.id);
  state.currentSession.activeRoomId = rooms.find((room) => room.id === state.currentSession.activeRoomId)?.id ?? rooms[0]?.id ?? null;
  saveState({ broadcast: false });
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
  elements.createFamilyForm.addEventListener("submit", handleCreateFamily);
  elements.joinFamilyForm.addEventListener("submit", handleJoinFamily);
  elements.roomList.addEventListener("click", handleRoomClick);
  elements.memberList.addEventListener("click", handleMemberClick);
  elements.savedProfilesList.addEventListener("click", handleProfileClick);
  elements.appProfileList.addEventListener("click", handleProfileClick);
  elements.inviteList.addEventListener("click", handleInviteClick);
  elements.createInviteButton.addEventListener("click", handleCreateInvite);
  elements.composerForm.addEventListener("submit", handleSendMessage);
  elements.imageInput.addEventListener("change", handleImageSelection);
  elements.removeImageButton.addEventListener("click", clearPendingImage);
  elements.openDrawerButton.addEventListener("click", () => setDrawer(true));
  elements.closeDrawerButton.addEventListener("click", () => setDrawer(false));
  elements.drawerScrim.addEventListener("click", () => setDrawer(false));
  elements.logoutButton.addEventListener("click", handleLogout);
  elements.muteToggleButton.addEventListener("click", toggleMuteRoom);
  elements.installButton.addEventListener("click", promptInstall);
  elements.notificationButton.addEventListener("click", requestNotificationPermission);
  elements.messageInput.addEventListener("input", autoResizeComposer);

  window.addEventListener("storage", (event) => {
    if (event.key === STORAGE_KEY) {
      syncState();
    }
  });

  if (syncChannel) {
    syncChannel.addEventListener("message", syncState);
  }

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    deferredInstallPrompt = event;
    renderInstallButton();
  });

  window.addEventListener("online", renderOfflineState);
  window.addEventListener("offline", renderOfflineState);

  document.addEventListener("visibilitychange", () => {
    const family = getCurrentFamily();
    const member = getCurrentMember();
    if (family && member) {
      touchMember(family.id, member.id);
      saveState();
      render();
    }
  });
}

function handleCreateFamily(event) {
  event.preventDefault();
  const familyName = elements.familyNameInput.value.trim();
  const adminName = elements.adminNameInput.value.trim();

  if (!familyName || !adminName) {
    showToast("가족 이름과 관리자 이름을 입력하세요.");
    return;
  }

  const familyId = createId("family");
  const adminId = createId("member");
  const familyRoomId = createId("room");
  const family = {
    id: familyId,
    name: familyName,
    createdAt: new Date().toISOString(),
    members: [createMember(adminId, adminName, "admin")],
    rooms: [{
      id: familyRoomId,
      familyId,
      type: "family",
      title: "가족 전체방",
      memberIds: [adminId],
      createdAt: new Date().toISOString(),
      mutedBy: {},
    }],
    invites: [],
    messages: [],
    settings: {
      allowGroupRooms: false,
    },
  };

  state.families.push(family);
  addSystemMessage(family, familyRoomId, `${familyName} 가족 채팅방이 만들어졌습니다.`);
  createInvite(family, adminId);
  createInvite(family, adminId);
  upsertDeviceProfile(family.id, adminId);
  state.currentSession = {
    familyId: family.id,
    memberId: adminId,
    activeRoomId: familyRoomId,
  };
  saveState();
  elements.createFamilyForm.reset();
  showToast("가족 그룹이 만들어졌습니다.");
  render();
}

function handleJoinFamily(event) {
  event.preventDefault();
  const inviteCode = elements.inviteCodeInput.value.trim().toUpperCase();
  const memberName = elements.memberNameInput.value.trim();

  if (!inviteCode || !memberName) {
    showToast("초대 코드와 이름을 입력하세요.");
    return;
  }

  const inviteMatch = findInvite(inviteCode);
  if (!inviteMatch) {
    showToast("유효한 초대 코드를 찾지 못했습니다.");
    return;
  }

  const { family, invite } = inviteMatch;
  if (invite.status !== "active") {
    showToast("이미 사용된 초대 코드입니다.");
    return;
  }

  const memberId = createId("member");
  const member = createMember(memberId, memberName, "member");
  const familyRoom = family.rooms.find((room) => room.type === "family");

  family.members.push(member);
  if (familyRoom && !familyRoom.memberIds.includes(memberId)) {
    familyRoom.memberIds.push(memberId);
  }
  invite.status = "used";
  invite.usedBy = memberId;
  invite.usedAt = new Date().toISOString();

  ensureDirectRoomsForFamily(family);
  if (familyRoom) {
    addSystemMessage(family, familyRoom.id, `${member.name}님이 가족 그룹에 참여했습니다.`);
  }

  upsertDeviceProfile(family.id, memberId);
  state.currentSession = {
    familyId: family.id,
    memberId,
    activeRoomId: familyRoom?.id ?? family.rooms[0]?.id ?? null,
  };
  saveState();
  elements.joinFamilyForm.reset();
  showToast(`${family.name} 가족에 참여했습니다.`);
  render();
}

function handleCreateInvite() {
  const family = getCurrentFamily();
  const member = getCurrentMember();

  if (!family || !member || member.role !== "admin") {
    showToast("관리자만 초대 코드를 만들 수 있습니다.");
    return;
  }

  const invite = createInvite(family, member.id);
  saveState();
  showToast(`${invite.code} 생성 완료`);
  render();
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

function handleRoomClick(event) {
  const button = event.target.closest("[data-room-id]");
  if (!button || !state.currentSession) {
    return;
  }

  state.currentSession.activeRoomId = button.dataset.roomId;
  markRoomRead();
  saveState();
  render();
  setDrawer(false);
}

function handleMemberClick(event) {
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

  const room = ensureDirectRoom(family, currentMember.id, targetId);
  state.currentSession.activeRoomId = room.id;
  markRoomRead();
  saveState();
  render();
  setDrawer(false);
}

function handleProfileClick(event) {
  const button = event.target.closest("[data-profile-key]");
  if (!button) {
    return;
  }

  const [familyId, memberId] = button.dataset.profileKey.split(":");
  const family = findFamily(familyId);
  const member = family ? findMember(family, memberId) : null;

  if (!family || !member) {
    showToast("저장된 프로필을 찾을 수 없습니다.");
    return;
  }

  state.currentSession = {
    familyId,
    memberId,
    activeRoomId: getRoomsForMember(family, memberId)[0]?.id ?? null,
  };
  touchMember(family.id, member.id);
  saveState();
  render();
}

function handleSendMessage(event) {
  event.preventDefault();
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

  family.messages.push({
    id: createId("message"),
    roomId: room.id,
    familyId: family.id,
    senderId: member.id,
    type: pendingImage ? "image" : "text",
    text,
    imageDataUrl: pendingImage?.dataUrl ?? null,
    createdAt: new Date().toISOString(),
    readBy: {
      [member.id]: new Date().toISOString(),
    },
  });

  touchMember(family.id, member.id);
  elements.messageInput.value = "";
  clearPendingImage();
  autoResizeComposer();
  markRoomRead();
  saveState();
  render();
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
  saveState();
  render();
}

function render() {
  const family = getCurrentFamily();
  const member = getCurrentMember();

  renderOfflineState();

  if (!family || !member) {
    elements.onboardingView.classList.remove("hidden");
    elements.appView.classList.add("hidden");
    setDrawer(false);
    renderSavedProfiles();
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

  renderSavedProfiles();
  renderRoomList(family, member, rooms);
  renderMemberList(family, member);
  renderInviteList(family, member);
  renderChat(family, member, activeRoom);
  renderInstallButton();
}

function renderSavedProfiles() {
  const profiles = state.deviceProfiles.map((profile) => {
    const family = findFamily(profile.familyId);
    const member = family ? findMember(family, profile.memberId) : null;
    if (!family || !member) {
      return null;
    }

    return {
      key: `${profile.familyId}:${profile.memberId}`,
      familyName: family.name,
      memberName: member.name,
      role: member.role,
    };
  }).filter(Boolean);

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

  const invites = [...family.invites].sort((left, right) => right.createdAt.localeCompare(left.createdAt));
  elements.inviteList.innerHTML = invites.length
    ? invites.map((invite) => `
      <article class="invite-card">
        <strong class="invite-code">${invite.code}</strong>
        <p>${invite.status === "active" ? "사용 가능" : invite.status === "used" ? "사용 완료" : "폐기됨"} · ${formatDateTime(invite.createdAt)}</p>
        <div class="message-card-footer">
          <span class="status-chip ${invite.status !== "active" ? "used" : ""}">${invite.status === "active" ? "active" : invite.status}</span>
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

  markRoomRead();
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

function markRoomRead() {
  const family = getCurrentFamily();
  const member = getCurrentMember();
  const room = getActiveRoom();

  if (!family || !member || !room) {
    return;
  }

  let changed = false;
  getMessagesForRoom(family, room.id).forEach((message) => {
    message.readBy = message.readBy || {};
    if (!message.readBy[member.id]) {
      message.readBy[member.id] = new Date().toISOString();
      changed = true;
    }
  });

  if (changed) {
    saveState({ broadcast: false });
  }
}

function toggleMuteRoom() {
  const room = getActiveRoom();
  const member = getCurrentMember();
  if (!room || !member) {
    return;
  }
  room.mutedBy = room.mutedBy || {};
  room.mutedBy[member.id] = !room.mutedBy[member.id];
  saveState();
  render();
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

function addSystemMessage(family, roomId, text) {
  family.messages.push({
    id: createId("message"),
    roomId,
    familyId: family.id,
    senderId: null,
    type: "system",
    text,
    imageDataUrl: null,
    createdAt: new Date().toISOString(),
    readBy: {},
  });
}

function createMember(memberId, name, role) {
  return {
    id: memberId,
    name,
    role,
    createdAt: new Date().toISOString(),
    lastSeenAt: new Date().toISOString(),
  };
}

function createInvite(family, createdBy) {
  const invite = {
    id: createId("invite"),
    code: `FAM-${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
    createdAt: new Date().toISOString(),
    createdBy,
    status: "active",
    usedBy: null,
    usedAt: null,
  };
  family.invites.push(invite);
  return invite;
}

function findInvite(code) {
  for (const family of state.families) {
    const invite = family.invites.find((item) => item.code === code);
    if (invite) {
      return { family, invite };
    }
  }
  return null;
}

function ensureDirectRoomsForFamily(family) {
  family.members.forEach((member) => {
    family.members.forEach((peer) => {
      if (member.id !== peer.id) {
        ensureDirectRoom(family, member.id, peer.id);
      }
    });
  });
}

function ensureDirectRoom(family, firstMemberId, secondMemberId) {
  const targetKey = [firstMemberId, secondMemberId].sort().join(":");
  const existing = family.rooms.find((room) => room.type === "dm" && room.memberIds.slice().sort().join(":") === targetKey);
  if (existing) {
    return existing;
  }

  const room = {
    id: createId("room"),
    familyId: family.id,
    type: "dm",
    title: "",
    memberIds: [firstMemberId, secondMemberId].sort(),
    createdAt: new Date().toISOString(),
    mutedBy: {},
  };
  family.rooms.push(room);
  return room;
}

function upsertDeviceProfile(familyId, memberId) {
  const existing = state.deviceProfiles.find((profile) => profile.familyId === familyId && profile.memberId === memberId);
  if (existing) {
    existing.savedAt = new Date().toISOString();
    return;
  }
  state.deviceProfiles.push({
    familyId,
    memberId,
    savedAt: new Date().toISOString(),
  });
}

function touchMember(familyId, memberId) {
  const family = findFamily(familyId);
  const member = family ? findMember(family, memberId) : null;
  if (member) {
    member.lastSeenAt = new Date().toISOString();
  }
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
  elements.installButton.disabled = !deferredInstallPrompt;
  elements.installButton.textContent = deferredInstallPrompt ? "앱 설치" : "설치 준비됨";
}

async function promptInstall() {
  if (!deferredInstallPrompt) {
    showToast("브라우저가 설치 프롬프트를 아직 제공하지 않았습니다.");
    return;
  }

  deferredInstallPrompt.prompt();
  await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  renderInstallButton();
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
      icon: "icons/icon-192.svg",
      badge: "icons/icon-192.svg",
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

function createId(prefix) {
  return `${prefix}-${Math.random().toString(36).slice(2, 10)}-${Date.now().toString(36)}`;
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.classList.remove("hidden");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    elements.toast.classList.add("hidden");
  }, 2200);
}
