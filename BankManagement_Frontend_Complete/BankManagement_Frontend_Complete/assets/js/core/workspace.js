(function () {
  const icon = (...args) => window.BankIcons.icon(...args);
  const UI = () => window.BankUI;
  const API = () => window.BankAPI;

  let state = {
    config: null,
    user: null,
    activeSection: '',
    loaded: new Set(),
    sectionData: {},
    filters: {},
    cache: {},
    activeReport: null
  };

  function initials(user) {
    const first = user?.FirstName || user?.firstName || user?.Username || user?.username || 'U';
    const last = user?.LastName || user?.lastName || '';
    return `${String(first)[0] || ''}${String(last)[0] || ''}`.toUpperCase();
  }

  function displayName(user) {
    const fullName = `${user?.FirstName || user?.firstName || ''} ${user?.LastName || user?.lastName || ''}`.trim();
    return fullName || user?.Username || user?.username || 'Bank user';
  }

  function groupedNav(items) {
    const groups = [];
    items.forEach((item) => {
      const groupName = item.group || 'Workspace';
      let group = groups.find((entry) => entry.name === groupName);
      if (!group) {
        group = { name: groupName, items: [] };
        groups.push(group);
      }
      group.items.push(item);
    });
    return groups;
  }

  function navButton(item) {
    return `<button class="nav-item ${item.id === state.activeSection ? 'active' : ''}" data-section-target="${item.id}" type="button">${icon(item.icon || 'dashboard', 19)}<span>${UI().escapeHtml(item.label)}</span>${item.count ? `<span class="nav-count">${item.count}</span>` : ''}</button>`;
  }

  function renderShell() {
    const config = state.config;
    const user = state.user;
    const groups = groupedNav(config.nav);
    document.body.classList.toggle('preview-mode', window.BankSession.isPreview());
    document.body.innerHTML = `
      <div class="preview-banner">${icon('eye', 16)} UI preview mode · data is simulated <a href="preview.html">Switch role</a></div>
      <div class="app-shell">
        <aside class="sidebar" id="sidebar">
          <div class="sidebar-head">
            <a class="sidebar-brand" href="#" data-section-target="${config.defaultSection || 'overview'}">
              <span class="brand-mark">${icon('bank', 23)}</span>
              <span><strong>BankManagement</strong><small>Secure banking suite</small></span>
            </a>
            <button class="btn btn-ghost btn-icon sidebar-close" type="button" id="sidebar-close" aria-label="Close navigation">${icon('close', 20)}</button>
          </div>
          <div class="sidebar-role"><div class="role-name">${icon(config.roleIcon || 'shield', 17)} ${UI().escapeHtml(config.role)} Workspace</div><p>${UI().escapeHtml(config.roleSummary || '')}</p></div>
          <nav class="sidebar-nav" aria-label="Main navigation">
            ${groups.map((group) => `<div class="nav-group-label">${UI().escapeHtml(group.name)}</div>${group.items.map(navButton).join('')}`).join('')}
          </nav>
          <div class="sidebar-foot">
            <div class="sidebar-user">
              <span class="avatar">${initials(user)}</span>
              <span class="user-copy"><strong>${UI().escapeHtml(displayName(user))}</strong><small>${UI().escapeHtml(user?.Username || user?.username || config.role)}</small></span>
              <button class="btn btn-ghost btn-icon" type="button" data-action="logout" title="Logout">${icon('logout', 18)}</button>
            </div>
          </div>
        </aside>
        <div class="sidebar-backdrop" id="sidebar-backdrop"></div>
        <div class="main-shell">
          <header class="topbar">
            <div class="topbar-left">
              <button class="btn btn-secondary btn-icon menu-toggle" id="menu-toggle" type="button" aria-label="Open navigation">${icon('menu', 20)}</button>
              <div class="breadcrumb">${icon('bank', 16)}<span>BankManagement</span>${icon('arrow', 14)}<strong id="breadcrumb-title">Dashboard</strong></div>
            </div>
            <div class="topbar-right">
              <div class="search-box topbar-search">${icon('search', 17)}<input class="input" id="global-search" placeholder="Search current table…"></div>
              <button class="system-status" id="system-status" type="button" data-action="api-settings" title="Backend connection settings"><i></i><span>Checking API…</span></button>
              <span class="badge badge-dark role-badge">${UI().escapeHtml(config.role)}</span>
              <button class="btn btn-secondary btn-icon" id="theme-toggle" type="button" title="Change theme">${icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon', 18)}</button>
            </div>
          </header>
          <main class="content" id="workspace-content">
            ${config.nav.map((item) => `<section class="section ${item.id === state.activeSection ? 'active' : ''}" id="section-${item.id}" data-section="${item.id}"><div class="section-head"><div><div class="kicker">${UI().escapeHtml(item.kicker || config.role)}</div><h1 class="page-title">${UI().escapeHtml(item.title || item.label)}</h1><p class="page-copy">${UI().escapeHtml(item.description || '')}</p></div><div class="section-actions" id="actions-${item.id}"></div></div><div id="content-${item.id}">${UI().loading()}</div></section>`).join('')}
          </main>
        </div>
        <nav class="mobile-nav" aria-label="Mobile navigation">${config.nav.slice(0, 5).map((item) => `<button type="button" class="${item.id === state.activeSection ? 'active' : ''}" data-section-target="${item.id}">${icon(item.icon || 'dashboard', 19)}<span>${UI().escapeHtml(item.shortLabel || item.label)}</span></button>`).join('')}</nav>
      </div>
      <div id="toast-stack" class="toast-stack"></div>`;
  }

  async function loadUser(config) {
    if (window.BankSession.isPreview()) {
      return window.BankMock.users[window.BankSession.previewRole()] || window.BankMock.users[config.role];
    }

    if (!window.BankSession.getToken()) {
      location.href = 'index.html';
      throw new Error('No session');
    }

    const response = await API().get('/api/auth/me');
    window.BankSession.updateUser(response.data);
    const actualRole = window.BankSession.highestRole(response.data);
    if (actualRole !== config.role && window.BankConfig.PAGE_BY_ROLE[actualRole]) {
      location.href = window.BankConfig.PAGE_BY_ROLE[actualRole];
      throw new Error('Redirecting');
    }
    return response.data;
  }

  function updateNavigation(sectionId) {
    document.querySelectorAll('[data-section-target]').forEach((element) => {
      element.classList.toggle('active', element.dataset.sectionTarget === sectionId);
    });
    document.querySelectorAll('.section').forEach((section) => {
      section.classList.toggle('active', section.dataset.section === sectionId);
    });
    const navItem = state.config.nav.find((item) => item.id === sectionId);
    const breadcrumb = document.querySelector('#breadcrumb-title');
    if (breadcrumb) breadcrumb.textContent = navItem?.label || sectionId;
    document.querySelector('#global-search')?.setAttribute('value', '');
  }

  async function showSection(sectionId, force = false) {
    const section = state.config.sections[sectionId];
    if (!section) return;
    state.activeSection = sectionId;
    localStorage.setItem(`${window.BankConfig.STORAGE_SECTION}.${state.config.role}`, sectionId);
    updateNavigation(sectionId);
    closeSidebar();
    if (!state.loaded.has(sectionId) || force) await loadSection(sectionId);
  }

  async function refreshSection() {
    state.loaded.delete(state.activeSection);
    state.cache = {};
    await loadSection(state.activeSection);
  }

  async function loadSection(sectionId) {
    const section = state.config.sections[sectionId];
    const container = document.querySelector(`#content-${sectionId}`);
    const actionsContainer = document.querySelector(`#actions-${sectionId}`);
    if (!section || !container) return;

    container.innerHTML = UI().loading();
    actionsContainer.innerHTML = typeof section.actions === 'function' ? section.actions(state) : (section.actions || '');

    try {
      const data = section.load ? await section.load(state) : null;
      state.sectionData[sectionId] = data;
      container.innerHTML = section.render ? section.render(data, state) : '';
      state.loaded.add(sectionId);
      if (section.afterRender) await section.afterRender(data, state);
    } catch (error) {
      container.innerHTML = `<div class="card"><div class="card-body"><div class="alert alert-danger"><strong>Unable to load this section.</strong><br>${UI().escapeHtml(error.message)}</div><div class="form-actions"><button class="btn btn-secondary" data-action="refresh-section">${icon('refresh', 17)} Try again</button><button class="btn btn-secondary" data-action="api-settings">${icon('plug', 17)} Connection settings</button></div></div></div>`;
      UI().toast(error.message, 'error');
    }
  }

  function openSidebar() {
    document.querySelector('#sidebar')?.classList.add('open');
    document.querySelector('#sidebar-backdrop')?.classList.add('show');
  }

  function closeSidebar() {
    document.querySelector('#sidebar')?.classList.remove('open');
    document.querySelector('#sidebar-backdrop')?.classList.remove('show');
  }

  function setupTheme() {
    const saved = localStorage.getItem(window.BankConfig.STORAGE_THEME)
      || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    document.documentElement.dataset.theme = saved;
  }

  function toggleTheme() {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    localStorage.setItem(window.BankConfig.STORAGE_THEME, next);
    const button = document.querySelector('#theme-toggle');
    if (button) button.innerHTML = icon(next === 'dark' ? 'sun' : 'moon', 18);
  }

  async function logout() {
    try {
      if (!window.BankSession.isPreview()) await API().post('/api/auth/logout');
    } catch (_) {
      // The local session still needs to be removed when the backend is unavailable.
    }
    window.BankSession.clear();
    window.BankSession.stopPreview();
    location.href = 'index.html';
  }

  function apiSettings() {
    UI().openForm({
      title: 'Backend connection',
      submitText: 'Save and test',
      intro: `<div class="alert alert-info"><strong>Current frontend origin:</strong> ${UI().escapeHtml(location.origin)}<br><strong>Backend API:</strong> ${UI().escapeHtml(window.BankConfig.getApiBaseUrl())}</div>`,
      fields: [
        {
          name: 'apiBaseUrl',
          label: 'Backend base URL',
          value: window.BankConfig.getApiBaseUrl(),
          required: true,
          placeholder: 'http://127.0.0.1:4000',
          help: 'Do not include /api at the end.'
        }
      ],
      onSubmit: async (data) => {
        window.BankConfig.setApiBaseUrl(data.apiBaseUrl);
        await API().health();
        UI().toast('Backend connection saved and verified.', 'success');
        setTimeout(() => location.reload(), 350);
      }
    });
  }

  function bindEvents() {
    document.addEventListener('click', async (event) => {
      const nav = event.target.closest('[data-section-target]');
      if (nav) {
        event.preventDefault();
        await showSection(nav.dataset.sectionTarget);
        return;
      }

      const actionElement = event.target.closest('[data-action]');
      if (!actionElement) return;
      const actionName = actionElement.dataset.action;
      if (actionName === 'logout') return logout();
      if (actionName === 'refresh-section') return refreshSection();
      if (actionName === 'api-settings') return apiSettings();

      const handler = state.config.actions?.[actionName];
      if (!handler) return;
      try {
        await handler({
          element: actionElement,
          state,
          refresh: refreshSection,
          showSection,
          api: API(),
          ui: UI()
        });
      } catch (error) {
        UI().toast(error.message, 'error');
      }
    });

    document.querySelector('#menu-toggle')?.addEventListener('click', openSidebar);
    document.querySelector('#sidebar-close')?.addEventListener('click', closeSidebar);
    document.querySelector('#sidebar-backdrop')?.addEventListener('click', closeSidebar);
    document.querySelector('#theme-toggle')?.addEventListener('click', toggleTheme);
    document.querySelector('#global-search')?.addEventListener('input', (event) => {
      const term = event.target.value.toLowerCase().trim();
      const section = document.querySelector('.section.active');
      section?.querySelectorAll('tbody tr').forEach((row) => {
        row.style.display = row.textContent.toLowerCase().includes(term) ? '' : 'none';
      });
    });
  }

  async function checkHealth() {
    const status = document.querySelector('#system-status');
    try {
      const response = await API().health();
      if (status) {
        status.classList.remove('offline');
        status.innerHTML = `<i></i><span>${UI().escapeHtml(response?.data?.databaseName || 'API connected')}</span>`;
      }
    } catch (_) {
      if (status) {
        status.classList.add('offline');
        status.innerHTML = '<i></i><span>API unavailable</span>';
      }
    }
  }

  async function init(config) {
    setupTheme();
    const savedSection = localStorage.getItem(`${window.BankConfig.STORAGE_SECTION}.${config.role}`);
    const validSavedSection = config.nav.some((item) => item.id === savedSection) ? savedSection : null;
    state = {
      config,
      user: null,
      activeSection: validSavedSection || config.defaultSection || config.nav[0].id,
      loaded: new Set(),
      sectionData: {},
      filters: {},
      cache: {},
      activeReport: null
    };

    try {
      state.user = await loadUser(config);
    } catch (error) {
      if (error.message === 'No session' || error.message === 'Redirecting') return;
      throw error;
    }

    renderShell();
    bindEvents();
    checkHealth();
    await showSection(state.activeSection, true);
  }

  window.BankWorkspace = {
    init,
    refreshSection,
    showSection,
    checkHealth,
    getState: () => state
  };
})();
