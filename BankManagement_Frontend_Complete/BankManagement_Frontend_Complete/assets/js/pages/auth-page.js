(function () {
  const UI = window.BankUI;
  const API = window.BankAPI;
  const Session = window.BankSession;
  const icon = window.BankIcons.icon;

  // Authentication must always use the real backend, even after a UI preview.
  Session.stopPreview();

  function message(text, type = 'error') {
    const element = document.querySelector('#auth-message');
    element.textContent = text;
    element.className = `auth-message show ${type}`;
  }

  function clearMessage() {
    const element = document.querySelector('#auth-message');
    element.className = 'auth-message';
    element.textContent = '';
  }

  function setTextIfPresent(selector, text) {
    const element = document.querySelector(selector);
    if (element) element.textContent = text;
  }

  function setConnectionClass(className) {
    const element = document.querySelector('#auth-api-url');
    if (!element) return;
    element.classList.remove('connection-ok', 'connection-error');
    element.classList.add(className);
  }

  function showTab(name) {
    document.querySelectorAll('[data-auth-tab]').forEach((button) => {
      button.classList.toggle('active', button.dataset.authTab === name);
    });
    document.querySelector('#login-form').classList.toggle('hidden', name !== 'login');
    document.querySelector('#signup-form').classList.toggle('hidden', name !== 'signup');
    document.querySelector('#auth-title').textContent = name === 'login' ? 'Welcome back' : 'Create customer access';
    document.querySelector('#auth-copy').textContent = name === 'login'
      ? 'Sign in to the workspace assigned to your highest effective role.'
      : 'Self-registration creates a customer profile and application login.';
    clearMessage();
  }

  function normalizeLoginUser(result, username) {
    const raw = result.data || {};
    return {
      ...raw,
      UserID: raw.UserID ?? raw.userID ?? result.output?.UserID,
      CustomerID: raw.CustomerID ?? raw.customerID ?? result.output?.CustomerID,
      EmployeeID: raw.EmployeeID ?? raw.employeeID ?? result.output?.EmployeeID,
      EffectiveRoles: raw.EffectiveRoles ?? raw.effectiveRoles ?? raw.Roles ?? result.output?.Roles,
      Username: raw.Username ?? username
    };
  }

  async function login(event) {
    event.preventDefault();
    clearMessage();
    const form = event.currentTarget;
    const button = form.querySelector('[type="submit"]');
    const data = Object.fromEntries(new FormData(form).entries());
    const persistent = form.elements.remember.checked;

    try {
      button.disabled = true;
      button.textContent = 'Signing in…';
      const result = await API.post('/api/auth/login', {
        username: data.username,
        password: data.password
      });
      const raw = result.data || {};
      const token = raw.sessionToken || raw.SessionToken || result.output?.SessionToken;
      if (!token) throw new Error('Login succeeded but the backend did not return a session token.');
      const user = normalizeLoginUser(result, data.username);
      Session.save(token, user, persistent);
      const me = await API.get('/api/auth/me');
      if (me.data) Session.save(token, me.data, persistent);
      location.href = Session.routeFor(Session.getUser() || user);
    } catch (error) {
      message(error.message);
      button.disabled = false;
      button.textContent = 'Sign in securely';
    }
  }

  async function signup(event) {
    event.preventDefault();
    clearMessage();
    const form = event.currentTarget;
    const button = form.querySelector('[type="submit"]');
    const body = Object.fromEntries(new FormData(form).entries());

    try {
      button.disabled = true;
      button.textContent = 'Creating account…';
      await API.post('/api/auth/signup', body);
      showTab('login');
      document.querySelector('#login-username').value = body.username;
      message('Customer access was created. You can sign in now.', 'success');
    } catch (error) {
      message(error.message);
    } finally {
      button.disabled = false;
      button.textContent = 'Create customer access';
    }
  }

  function initialHighAdminSetup() {
    UI.openForm({
      title: 'Create initial HighAdmin',
      submitText: 'Create initial HighAdmin',
      size: 'lg',
      intro: '<div class="alert alert-warning"><strong>One-time bootstrap operation.</strong><br>This endpoint succeeds only when the database has no HighAdmin yet. Do not use it for normal manager creation.</div>',
      fields: [
        { name: 'username', label: 'Username', required: true, autocomplete: 'off' },
        { name: 'password', label: 'Password', type: 'password', required: true, autocomplete: 'new-password' },
        { name: 'firstName', label: 'First name', required: true },
        { name: 'lastName', label: 'Last name', required: true },
        { name: 'nationalID', label: 'National ID', required: true },
        { name: 'birthDate', label: 'Birth date', type: 'date', required: true },
        { name: 'phone', label: 'Phone', required: true },
        { name: 'email', label: 'Email', type: 'email', required: true },
        { name: 'address', label: 'Address', type: 'textarea', full: true }
      ],
      onSubmit: async (data) => {
        await API.post('/api/setup/initial-high-admin', data);
        document.querySelector('#login-username').value = data.username;
        message('Initial HighAdmin was created. Sign in with the new credentials.', 'success');
      }
    });
  }

  function connectionSettings() {
    UI.openForm({
      title: 'Backend connection',
      submitText: 'Save and test',
      intro: `<div class="alert alert-info"><strong>Frontend origin:</strong> ${UI.escapeHtml(location.origin)}<br>The backend must allow this origin in its CORS_ORIGIN setting.</div>`,
      fields: [{
        name: 'apiBaseUrl',
        label: 'Backend base URL',
        value: window.BankConfig.getApiBaseUrl(),
        required: true,
        placeholder: 'http://127.0.0.1:4000',
        help: 'Do not add /api at the end.'
      }],
      onSubmit: async (data) => {
        window.BankConfig.setApiBaseUrl(data.apiBaseUrl);
        await API.health();
        const apiUrl = window.BankConfig.getApiBaseUrl();
        setTextIfPresent('#api-address', apiUrl);
        setTextIfPresent('#auth-api-url', apiUrl);
        setConnectionClass('connection-ok');
        UI.toast('Backend connection verified.', 'success');
      }
    });
  }

  async function checkConnection() {
    const apiUrl = window.BankConfig.getApiBaseUrl();
    setTextIfPresent('#api-address', apiUrl);
    setTextIfPresent('#auth-api-url', apiUrl);
    try {
      await API.health();
      setConnectionClass('connection-ok');
    } catch (_) {
      setConnectionClass('connection-error');
    }
  }

  document.querySelectorAll('[data-auth-tab]').forEach((button) => {
    button.addEventListener('click', () => showTab(button.dataset.authTab));
  });
  document.querySelector('#login-form').addEventListener('submit', login);
  document.querySelector('#signup-form').addEventListener('submit', signup);
  document.querySelector('#auth-api-settings').addEventListener('click', connectionSettings);
  document.querySelector('#initial-highadmin-setup').addEventListener('click', initialHighAdminSetup);

  document.querySelectorAll('[data-password-toggle]').forEach((button) => {
    button.addEventListener('click', () => {
      const input = document.querySelector(`#${button.dataset.passwordToggle}`);
      input.type = input.type === 'password' ? 'text' : 'password';
      button.innerHTML = icon('eye', 18);
    });
  });

  if (Session.getToken()) {
    const continueBox = document.querySelector('#existing-session');
    continueBox.classList.remove('hidden');
    continueBox.querySelector('button').addEventListener('click', () => {
      location.href = Session.routeFor(Session.getUser());
    });
  }

  if (new URLSearchParams(location.search).get('expired')) {
    message('Your previous session is no longer valid. Sign in again.', 'error');
  }

  checkConnection();
})();
