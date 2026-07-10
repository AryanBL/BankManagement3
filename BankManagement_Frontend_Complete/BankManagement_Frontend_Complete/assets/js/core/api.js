(function () {
  function buildUrl(path) {
    if (/^https?:\/\//i.test(path)) return path;
    return `${window.BankConfig.getApiBaseUrl()}${path.startsWith('/') ? path : `/${path}`}`;
  }

  function buildQuery(params = {}) {
    const search = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      if (value === undefined || value === null || value === '') return;
      search.set(key, String(value));
    });
    const result = search.toString();
    return result ? `?${result}` : '';
  }

  async function request(path, options = {}) {
    if (window.BankSession.isPreview()) return window.BankMock.respond(path, options);

    const headers = new Headers(options.headers || {});
    const token = window.BankSession.getToken();
    if (token && !headers.has('Authorization')) headers.set('Authorization', `Bearer ${token}`);
    headers.set('Accept', 'application/json');

    let body = options.body;
    if (body !== undefined && body !== null && !(body instanceof FormData) && typeof body !== 'string') {
      headers.set('Content-Type', 'application/json');
      body = JSON.stringify(body);
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), options.timeout || window.BankConfig.REQUEST_TIMEOUT_MS);

    let response;
    try {
      response = await fetch(buildUrl(path), {
        ...options,
        headers,
        body,
        signal: options.signal || controller.signal
      });
    } catch (error) {
      if (error.name === 'AbortError') {
        const timeoutError = new Error('The backend did not respond before the request timeout.');
        timeoutError.code = 'REQUEST_TIMEOUT';
        throw timeoutError;
      }
      const networkError = new Error(`Cannot reach the backend at ${window.BankConfig.getApiBaseUrl()}. Check that it is running and that CORS allows this frontend origin.`);
      networkError.code = 'NETWORK_ERROR';
      networkError.cause = error;
      throw networkError;
    } finally {
      clearTimeout(timeout);
    }

    const contentType = response.headers.get('content-type') || '';
    let payload;
    if (contentType.includes('application/json')) {
      try { payload = await response.json(); }
      catch (_) { payload = { success: response.ok, data: null }; }
    } else {
      payload = { success: response.ok, data: await response.text() };
    }

    if (!response.ok || payload?.success === false) {
      const message = payload?.error?.message || payload?.message || `Request failed with HTTP ${response.status}.`;
      const error = new Error(message);
      error.status = response.status;
      error.payload = payload;
      error.url = buildUrl(path);
      if (response.status === 401 && !String(path).includes('/api/auth/login')) {
        window.BankSession.clear();
        if (!location.pathname.endsWith('index.html') && !location.pathname.endsWith('/')) {
          setTimeout(() => { location.href = 'index.html?expired=1'; }, 500);
        }
      }
      throw error;
    }

    return payload;
  }

  const get = (path, params) => request(`${path}${params ? buildQuery(params) : ''}`);
  const post = (path, body) => request(path, { method: 'POST', body });
  const put = (path, body) => request(path, { method: 'PUT', body });
  const del = (path, body) => request(path, { method: 'DELETE', body });
  const health = () => request('/api/health', { timeout: 8000 });

  window.BankAPI = { request, get, post, put, delete: del, health, buildQuery, buildUrl };
})();
