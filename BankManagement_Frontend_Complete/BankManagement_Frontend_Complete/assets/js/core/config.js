(function () {
  const DEFAULT_API_BASE_URL = 'http://127.0.0.1:4000';
  const STORAGE_API_BASE = 'bank.apiBaseUrl';

  function cleanBaseUrl(value) {
    const text = String(value || '').trim().replace(/\/+$/, '');
    return text || DEFAULT_API_BASE_URL;
  }

  function getApiBaseUrl() {
    const queryValue = new URLSearchParams(location.search).get('api');
    if (queryValue) {
      const cleaned = cleanBaseUrl(queryValue);
      localStorage.setItem(STORAGE_API_BASE, cleaned);
      return cleaned;
    }
    return cleanBaseUrl(localStorage.getItem(STORAGE_API_BASE) || DEFAULT_API_BASE_URL);
  }

  function setApiBaseUrl(value) {
    const cleaned = cleanBaseUrl(value);
    localStorage.setItem(STORAGE_API_BASE, cleaned);
    return cleaned;
  }

  function resetApiBaseUrl() {
    localStorage.removeItem(STORAGE_API_BASE);
    return DEFAULT_API_BASE_URL;
  }

  window.BankConfig = {
    APP_NAME: 'BankManagement',
    DEFAULT_API_BASE_URL,
    STORAGE_API_BASE,
    STORAGE_TOKEN: 'bank.sessionToken',
    STORAGE_USER: 'bank.currentUser',
    STORAGE_THEME: 'bank.theme',
    STORAGE_SECTION: 'bank.activeSection',
    STORAGE_ACTIVITY: 'bank.activityLog',
    PREVIEW_ROLE: 'bank.previewRole',
    REQUEST_TIMEOUT_MS: 30000,
    ROLE_HIERARCHY: ['Customer', 'Employee', 'Admin', 'HighAdmin'],
    PAGE_BY_ROLE: {
      Customer: 'customer.html',
      Employee: 'employee.html',
      Admin: 'admin.html',
      HighAdmin: 'highadmin.html'
    },
    get API_BASE_URL() { return getApiBaseUrl(); },
    getApiBaseUrl,
    setApiBaseUrl,
    resetApiBaseUrl
  };
})();
