(function () {
  const C = window.BankConfig;

  function read(key) {
    return localStorage.getItem(key) || sessionStorage.getItem(key) || '';
  }

  function getToken() {
    return read(C.STORAGE_TOKEN);
  }

  function getUser() {
    try {
      return JSON.parse(read(C.STORAGE_USER) || 'null');
    } catch (_) {
      return null;
    }
  }

  function save(token, user, persist = true) {
    const target = persist ? localStorage : sessionStorage;
    const other = persist ? sessionStorage : localStorage;
    if (token) target.setItem(C.STORAGE_TOKEN, token);
    if (user) target.setItem(C.STORAGE_USER, JSON.stringify(user));
    other.removeItem(C.STORAGE_TOKEN);
    other.removeItem(C.STORAGE_USER);
  }

  function updateUser(user) {
    const persistent = Boolean(localStorage.getItem(C.STORAGE_TOKEN));
    save(getToken(), user, persistent);
  }

  function clear() {
    [localStorage, sessionStorage].forEach((store) => {
      store.removeItem(C.STORAGE_TOKEN);
      store.removeItem(C.STORAGE_USER);
    });
  }

  function normalizeRoles(user) {
    const raw = user?.roles || user?.EffectiveRoles || user?.effectiveRoles || user?.Roles || '';
    if (Array.isArray(raw)) return raw.map(String).map((role) => role.trim()).filter(Boolean);
    return String(raw).split(',').map((role) => role.trim()).filter(Boolean);
  }

  function hasRole(user, role) {
    return normalizeRoles(user).includes(role);
  }

  function highestRole(user) {
    const roles = normalizeRoles(user);
    return [...C.ROLE_HIERARCHY].reverse().find((role) => roles.includes(role)) || 'Customer';
  }

  function routeFor(user) {
    return C.PAGE_BY_ROLE[highestRole(user)] || 'customer.html';
  }

  function isPreview() {
    return Boolean(sessionStorage.getItem(C.PREVIEW_ROLE));
  }

  function previewRole() {
    return sessionStorage.getItem(C.PREVIEW_ROLE) || '';
  }

  function startPreview(role) {
    sessionStorage.setItem(C.PREVIEW_ROLE, role);
  }

  function stopPreview() {
    sessionStorage.removeItem(C.PREVIEW_ROLE);
  }

  const previewParam = new URLSearchParams(location.search).get('preview');
  if (previewParam && C.PAGE_BY_ROLE[previewParam]) startPreview(previewParam);

  window.BankSession = {
    getToken,
    getUser,
    save,
    updateUser,
    clear,
    normalizeRoles,
    hasRole,
    highestRole,
    routeFor,
    isPreview,
    previewRole,
    startPreview,
    stopPreview
  };
})();
