(function () {
  const icon = (...args) => window.BankIcons.icon(...args);
  const moneyKeys = /amount|balance|salary|deposit|payment|principal|interest|penalty|outstanding/i;

  const DATE_ONLY_KEYS = new Set([
    'birthdate', 'registrationdate', 'opendate', 'closedate', 'hiredate',
    'startdate', 'enddate', 'duedate', 'paiddate', 'effectivedate',
    'terminationdate', 'transactionday', 'oldestoverdueduedate',
    'currentbranchstartdate'
  ]);

  const DATE_TIME_KEYS = new Set([
    'date', 'transactiondate', 'readytocompleteat', 'initialdepositreadytocompleteat',
    'paymentreadytocompleteat', 'actiondate', 'entrydate', 'logintime',
    'logouttime', 'expiresat', 'sessionexpiresat', 'lastactivityat',
    'createdat', 'updatedat', 'processedat', 'completedat', 'cancelledat',
    'currentmanagerdecisiondate', 'destinationmanagerdecisiondate'
  ]);

  function compactKey(key) {
    return String(key || '').replace(/[^a-z0-9]/gi, '').toLowerCase();
  }

  function dateKindForKey(key, explicitKind = null) {
    const normalizedExplicit = String(explicitKind || '').toLowerCase();
    if (normalizedExplicit === 'date' || normalizedExplicit === 'datetime') return normalizedExplicit;

    const compact = compactKey(key);
    if (DATE_TIME_KEYS.has(compact)) return 'datetime';
    if (DATE_ONLY_KEYS.has(compact)) return 'date';

    if (/(?:timestamp|datetime|time|expiresat|createdat|updatedat|processedat|completedat|cancelledat|readytocompleteat)$/.test(compact)) return 'datetime';
    if (/(?:date|day)$/.test(compact)) return 'date';
    return null;
  }

  function parseDateValue(value, kind = 'datetime') {
    if (value === null || value === undefined || value === '') return null;
    if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : new Date(value.getTime());

    const raw = String(value).trim();
    if (!raw) return null;

    const dotNet = raw.match(/^\/Date\((-?\d+)\)\/$/);
    if (dotNet) {
      const parsed = new Date(Number(dotNet[1]));
      return Number.isNaN(parsed.getTime()) ? null : parsed;
    }

    const parts = raw.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T\s](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,7}))?)?)?/);
    if (parts) {
      const [, year, month, day, hour = '0', minute = '0', second = '0', fraction = '0'] = parts;
      const hasZone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw);

      if (kind === 'date') {
        // New backend responses send SQL DATE as YYYY-MM-DD. For legacy
        // zoned values, first convert the instant to the browser's local
        // calendar date so a local-midnight SQL DATE does not move a day.
        if (hasZone) {
          const zoned = new Date(raw);
          if (!Number.isNaN(zoned.getTime())) {
            return new Date(zoned.getFullYear(), zoned.getMonth(), zoned.getDate());
          }
        }
        const localDate = new Date(Number(year), Number(month) - 1, Number(day));
        return Number.isNaN(localDate.getTime()) ? null : localDate;
      }

      if (!hasZone) {
        const milliseconds = Number((fraction + '000').slice(0, 3));
        const localDateTime = new Date(
          Number(year), Number(month) - 1, Number(day),
          Number(hour), Number(minute), Number(second), milliseconds
        );
        return Number.isNaN(localDateTime.getTime()) ? null : localDateTime;
      }
    }

    const parsed = new Date(raw);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[character]));
  }

  function humanize(key) {
    return String(key || '')
      .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
      .replace(/[_-]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .replace(/^./, (character) => character.toUpperCase());
  }

  function formatMoney(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return value ?? '—';
    return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(number);
  }

  function formatDate(value, options = {}) {
    if (value === null || value === undefined || value === '') return '—';
    const suppliedKind = typeof options === 'string' ? options : options.kind;
    const raw = String(value);
    const inferredKind = suppliedKind || (/^\d{4}-\d{2}-\d{2}$/.test(raw.trim()) ? 'date' : 'datetime');
    const date = parseDateValue(value, inferredKind);
    if (!date) return String(value);

    const locale = document.documentElement.lang || navigator.language || undefined;
    const formatOptions = inferredKind === 'date'
      ? { year: 'numeric', month: 'short', day: '2-digit' }
      : {
          year: 'numeric', month: 'short', day: '2-digit',
          hour: '2-digit', minute: '2-digit', second: '2-digit',
          timeZoneName: 'short'
        };

    return new Intl.DateTimeFormat(locale, formatOptions).format(date);
  }

  function formatEmbeddedDates(value) {
    const text = String(value ?? '');
    if (!text) return text;

    const dateTimePattern = /\b\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,7})?)?(?:Z|[+-]\d{2}:?\d{2})?\b/g;
    const withDateTimes = text.replace(dateTimePattern, (match) => formatDate(match, { kind: 'datetime' }));
    const dateOnlyPattern = /\b\d{4}-\d{2}-\d{2}\b/g;
    return withDateTimes.replace(dateOnlyPattern, (match) => formatDate(match, { kind: 'date' }));
  }

  function dateSortValue(value, kind = 'datetime') {
    const date = parseDateValue(value, kind);
    return date ? date.getTime() : 0;
  }

  function statusBadge(value) {
    const status = String(value ?? 'Unknown');
    const cssClass = /active|completed|approved|paid|success|working/i.test(status)
      ? 'badge-success'
      : /pending|processing|dormant|onleave|on leave/i.test(status)
        ? 'badge-warning'
        : /closed|failed|rejected|overdue|suspended|frozen|inactive|terminated|cancelled/i.test(status)
          ? 'badge-danger'
          : 'badge-info';
    return `<span class="badge ${cssClass}">${escapeHtml(status)}</span>`;
  }

  function formatCell(key, value, options = {}) {
    if (value === null || value === undefined || value === '') return '<span class="muted">—</span>';
    if (/status|isactive|workingstatus/i.test(key)) {
      return statusBadge(typeof value === 'boolean' ? (value ? 'Active' : 'Inactive') : value);
    }
    if (moneyKeys.test(key) && !/rate/i.test(key)) return formatMoney(value);
    if (/rate/i.test(key) && Number.isFinite(Number(value))) return `${escapeHtml(value)}%`;

    const dateKind = dateKindForKey(key, options.dateKind);
    if (dateKind) {
      const formatted = formatDate(value, { kind: dateKind });
      const date = parseDateValue(value, dateKind);
      const title = date ? `${date.toString()} | Source: ${String(value)}` : String(value);
      const datetime = date ? date.toISOString() : '';
      return `<time${datetime ? ` datetime="${escapeHtml(datetime)}"` : ''} title="${escapeHtml(title)}">${escapeHtml(formatted)}</time>`;
    }
    if (typeof value === 'boolean') return value ? 'Yes' : 'No';
    if (typeof value === 'object') return `<code>${escapeHtml(JSON.stringify(value))}</code>`;
    return escapeHtml(formatEmbeddedDates(value));
  }

  function unionKeys(rows) {
    const found = [];
    rows.forEach((row) => {
      Object.keys(row || {}).forEach((key) => {
        if (!found.includes(key)) found.push(key);
      });
    });
    return found;
  }

  function renderTable(inputRows, options = {}) {
    const rows = Array.isArray(inputRows) ? inputRows : inputRows ? [inputRows] : [];
    if (!rows.length) {
      return emptyState(options.emptyTitle || 'No records found', options.emptyText || 'There is no data to display.');
    }

    let columns = options.columns || unionKeys(rows).map((key) => ({ key, label: humanize(key) }));
    const hidden = new Set(options.hide || []);
    columns = columns.filter((column) => !hidden.has(column.key));
    if (options.maxColumns && columns.length > options.maxColumns) columns = columns.slice(0, options.maxColumns);

    const actionHead = options.actions ? '<th class="sticky-actions">Actions</th>' : '';
    const head = columns.map((column) => `<th>${escapeHtml(column.label || humanize(column.key))}</th>`).join('') + actionHead;
    const body = rows.map((row, rowIndex) => {
      const cells = columns.map((column) => {
        const value = row?.[column.key];
        const explicitDateKind = column.dateKind || column.type || options.dateFields?.[column.key];
        return `<td>${column.render ? column.render(value, row, rowIndex) : formatCell(column.key, value, { dateKind: explicitDateKind })}</td>`;
      }).join('');
      const actions = options.actions
        ? `<td class="sticky-actions"><div class="table-actions">${options.actions(row, rowIndex)}</div></td>`
        : '';
      return `<tr>${cells}${actions}</tr>`;
    }).join('');

    return `<div class="table-wrap"><table class="data-table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
  }

  function renderRecordsets(data, options = {}) {
    const sets = Array.isArray(data) && data.some(Array.isArray)
      ? data.filter(Array.isArray)
      : [Array.isArray(data) ? data : data ? [data] : []];
    return sets.map((set, index) => {
      const title = options.titles?.[index] || (sets.length > 1 ? `Result set ${index + 1}` : 'Details');
      const perSetDateFields = options.dateFieldsBySet?.[index] || options.dateFields || options.tableOptions?.dateFields || {};
      const tableOptions = { ...(options.tableOptions || {}), dateFields: perSetDateFields };
      return `<section class="recordset"><h4>${escapeHtml(title)}</h4>${renderTable(set, tableOptions)}</section>`;
    }).join('');
  }

  function keyValue(data, hidden = []) {
    const row = Array.isArray(data) ? data[0] : data;
    if (!row || typeof row !== 'object') return emptyState('No details', 'No detail record was returned.');
    return `<div class="detail-grid">${Object.entries(row)
      .filter(([key]) => !hidden.includes(key))
      .map(([key, value]) => `<div class="detail-item"><span>${escapeHtml(humanize(key))}</span><strong>${formatCell(key, value)}</strong></div>`)
      .join('')}</div>`;
  }

  function emptyState(title, text) {
    return `<div class="empty-state"><div class="empty-icon">${icon('reports', 24)}</div><strong>${escapeHtml(title)}</strong><div>${escapeHtml(text)}</div></div>`;
  }

  function loading() {
    return `<div class="loading-list">${Array.from({ length: 5 }, () => '<div class="loading-skeleton"></div>').join('')}</div>`;
  }

  function toast(message, type = 'info', timeout = 4200) {
    const stack = document.querySelector('#toast-stack') || (() => {
      const element = document.createElement('div');
      element.id = 'toast-stack';
      element.className = 'toast-stack';
      document.body.appendChild(element);
      return element;
    })();
    const element = document.createElement('div');
    element.className = `toast toast-${type}`;
    element.innerHTML = `<div>${icon(type === 'success' ? 'check' : type === 'error' ? 'alert' : 'bell', 20)}</div><div><strong>${escapeHtml(type === 'error' ? 'Action failed' : type === 'success' ? 'Completed' : 'Notice')}</strong><div class="muted">${escapeHtml(message)}</div></div>`;
    stack.appendChild(element);
    setTimeout(() => element.remove(), timeout);
  }

  function closeModal() {
    document.querySelector('#bank-modal')?.remove();
  }

  function openModal({ title, content, size = '', footer = '' }) {
    closeModal();
    const wrapper = document.createElement('div');
    wrapper.id = 'bank-modal';
    wrapper.className = 'modal-backdrop';
    wrapper.innerHTML = `<section class="modal ${size === 'lg' ? 'modal-lg' : ''}" role="dialog" aria-modal="true" aria-label="${escapeHtml(title)}"><header class="modal-head"><h3>${escapeHtml(title)}</h3><button class="btn btn-ghost btn-icon" type="button" data-close-modal aria-label="Close">${icon('close', 20)}</button></header><div class="modal-body">${content}</div>${footer ? `<footer class="card-footer">${footer}</footer>` : ''}</section>`;
    document.body.appendChild(wrapper);
    wrapper.addEventListener('click', (event) => {
      if (event.target === wrapper || event.target.closest('[data-close-modal]')) closeModal();
    });
    const escapeHandler = (event) => {
      if (event.key === 'Escape') {
        closeModal();
        document.removeEventListener('keydown', escapeHandler);
      }
    };
    document.addEventListener('keydown', escapeHandler);
    return wrapper;
  }

  function fieldHtml(field) {
    if (field.type === 'hidden') return `<input type="hidden" name="${escapeHtml(field.name)}" value="${escapeHtml(field.value ?? '')}">`;
    const required = field.required ? 'required' : '';
    const disabled = field.disabled ? 'disabled' : '';
    const readonly = field.readonly ? 'readonly' : '';
    const value = field.value ?? '';
    const fieldClass = field.full ? 'field full' : 'field';
    const label = `<label>${escapeHtml(field.label)}${field.required ? ' *' : ''}</label>`;
    const help = field.help ? `<small class="field-help">${escapeHtml(field.help)}</small>` : '';

    if (field.type === 'textarea') {
      return `<div class="${fieldClass}">${label}<textarea class="textarea" name="${escapeHtml(field.name)}" placeholder="${escapeHtml(field.placeholder || '')}" ${required} ${disabled} ${readonly}>${escapeHtml(value)}</textarea>${help}</div>`;
    }

    if (field.type === 'select') {
      const options = (field.options || []).map((entry) => {
        const option = typeof entry === 'object' ? entry : { value: entry, label: entry };
        return `<option value="${escapeHtml(option.value)}" ${String(option.value) === String(value) ? 'selected' : ''}>${escapeHtml(option.label)}</option>`;
      }).join('');
      return `<div class="${fieldClass}">${label}<select class="select" name="${escapeHtml(field.name)}" ${required} ${disabled}><option value="">${escapeHtml(field.emptyLabel || 'Select…')}</option>${options}</select>${help}</div>`;
    }

    if (field.type === 'checkbox') {
      return `<div class="${fieldClass}"><label class="checkbox"><input type="checkbox" name="${escapeHtml(field.name)}" ${field.checked || value === true || value === 'true' ? 'checked' : ''}> ${escapeHtml(field.label)}</label>${help}</div>`;
    }

    const listId = Array.isArray(field.suggestions) && field.suggestions.length
      ? `field-list-${String(field.name).replace(/[^a-zA-Z0-9_-]/g, '-')}`
      : '';
    const datalist = listId
      ? `<datalist id="${escapeHtml(listId)}">${field.suggestions.map((entry) => {
          const suggestion = typeof entry === 'object' ? entry : { value: entry, label: entry };
          return `<option value="${escapeHtml(suggestion.value)}">${escapeHtml(suggestion.label)}</option>`;
        }).join('')}</datalist>`
      : '';
    return `<div class="${fieldClass}">${label}<input class="input" type="${escapeHtml(field.type || 'text')}" name="${escapeHtml(field.name)}" value="${escapeHtml(value)}" placeholder="${escapeHtml(field.placeholder || '')}" ${listId ? `list="${escapeHtml(listId)}"` : ''} ${field.min !== undefined ? `min="${escapeHtml(field.min)}"` : ''} ${field.max !== undefined ? `max="${escapeHtml(field.max)}"` : ''} ${field.step !== undefined ? `step="${escapeHtml(field.step)}"` : ''} ${field.pattern ? `pattern="${escapeHtml(field.pattern)}"` : ''} ${field.autocomplete ? `autocomplete="${escapeHtml(field.autocomplete)}"` : ''} ${required} ${disabled} ${readonly}>${datalist}${help}</div>`;
  }

  function normalizeFormData(form, fields) {
    const data = Object.fromEntries(new FormData(form).entries());
    fields.forEach((field) => {
      if (field.type === 'checkbox') data[field.name] = form.elements[field.name]?.checked || false;
      if ((['number', 'range'].includes(field.type) || field.valueType === 'number') && data[field.name] !== '') {
        data[field.name] = Number(data[field.name]);
      }
      if (field.trim !== false && typeof data[field.name] === 'string') data[field.name] = data[field.name].trim();
      if (data[field.name] === '' && field.omitEmpty !== false) delete data[field.name];
    });
    return data;
  }

  function openForm({ title, fields, submitText = 'Submit', onSubmit, size = '', intro = '' }) {
    const content = `<form id="bank-action-form">${intro ? `<div class="form-intro">${intro}</div>` : ''}<div class="form-grid">${fields.map(fieldHtml).join('')}</div><div class="form-actions"><button class="btn btn-secondary" type="button" data-close-modal>Cancel</button><button class="btn btn-primary" type="submit">${escapeHtml(submitText)}</button></div></form>`;
    const modal = openModal({ title, content, size });
    const form = modal.querySelector('#bank-action-form');
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = form.querySelector('[type="submit"]');
      const originalText = button.textContent;
      const data = normalizeFormData(form, fields);
      try {
        button.disabled = true;
        button.textContent = 'Working…';
        await onSubmit(data, form);
        if (modal.isConnected) modal.remove();
      } catch (error) {
        toast(error.message, 'error');
        button.disabled = false;
        button.textContent = originalText;
      }
    });
    form.querySelector('input:not([type="hidden"]),select,textarea')?.focus();
    return modal;
  }

  function confirmAction({ title = 'Confirm action', message, confirmText = 'Confirm', danger = false, onConfirm }) {
    const content = `<div class="alert ${danger ? 'alert-danger' : 'alert-warning'}">${escapeHtml(message)}</div><div class="form-actions"><button class="btn btn-secondary" data-close-modal>Cancel</button><button class="btn ${danger ? 'btn-danger' : 'btn-primary'}" id="confirm-action">${escapeHtml(confirmText)}</button></div>`;
    const modal = openModal({ title, content });
    modal.querySelector('#confirm-action').addEventListener('click', async (event) => {
      const button = event.currentTarget;
      try {
        button.disabled = true;
        button.textContent = 'Working…';
        await onConfirm();
        if (modal.isConnected) modal.remove();
      } catch (error) {
        toast(error.message, 'error');
        button.disabled = false;
        button.textContent = confirmText;
      }
    });
  }

  function statCard(label, value, meta, iconName = 'trend', color = 'var(--teal-600)', tint = 'rgba(20,184,166,.12)') {
    return `<article class="card stat-card" style="--stat-color:${color};--stat-tint:${tint}"><div class="stat-top"><div><div class="stat-label">${escapeHtml(label)}</div><div class="stat-value">${escapeHtml(value)}</div><div class="stat-meta">${escapeHtml(meta || '')}</div></div><div class="stat-icon">${icon(iconName, 21)}</div></div></article>`;
  }

  function downloadCSV(rows, fileName = 'report.csv', options = {}) {
    if (!Array.isArray(rows) || !rows.length) {
      toast('There is no data to export.', 'info');
      return;
    }
    const keys = unionKeys(rows);
    const exportValue = (key, value) => {
      const kind = dateKindForKey(key, options.dateFields?.[key]);
      if (kind && value !== null && value !== undefined && value !== '') {
        return formatDate(value, { kind });
      }
      if (value && typeof value === 'object') return JSON.stringify(value);
      return formatEmbeddedDates(String(value ?? ''));
    };
    const csvRows = [
      keys.map((key) => `"${humanize(key).replace(/"/g, '""')}"`).join(','),
      ...rows.map((row) => keys.map((key) => `"${exportValue(key, row?.[key]).replace(/"/g, '""')}"`).join(','))
    ];
    const blob = new Blob([`\uFEFF${csvRows.join('\r\n')}`], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function filterSummary(filters = {}) {
    const active = Object.entries(filters).filter(([, value]) => value !== '' && value !== undefined && value !== null && value !== false);
    if (!active.length) return '';
    return `<div class="filter-summary"><strong>Active filters:</strong>${active.map(([key, value]) => {
      const kind = dateKindForKey(key);
      const displayValue = kind ? formatDate(value, { kind }) : value;
      return `<span class="badge badge-info">${escapeHtml(humanize(key))}: ${escapeHtml(displayValue)}</span>`;
    }).join('')}</div>`;
  }

  window.BankUI = {
    escapeHtml,
    humanize,
    formatMoney,
    formatDate,
    formatEmbeddedDates,
    parseDateValue,
    dateKindForKey,
    dateSortValue,
    statusBadge,
    formatCell,
    renderTable,
    renderRecordsets,
    keyValue,
    emptyState,
    loading,
    toast,
    openModal,
    closeModal,
    openForm,
    confirmAction,
    statCard,
    downloadCSV,
    filterSummary
  };
})();
