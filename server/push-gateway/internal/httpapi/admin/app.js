(() => {
  'use strict';

  const TOKEN_KEY = 'trackerone.admin.token';
  const state = {
    token: sessionStorage.getItem(TOKEN_KEY) || '',
    audit: { userId: 1, serverId: 1, limit: 50, cursor: '' },
    loaded: [],
  };

  const $ = (id) => document.getElementById(id);

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function setStatus(id, text, tone) {
    const node = $(id);
    node.textContent = text || '';
    node.className = tone ? `status ${tone}` : 'muted';
  }

  function pushLabel(status) {
    switch (status) {
      case 'sent':
        return '已推送';
      case 'no_alias':
        return '无设备别名';
      case 'failed':
        return '推送失败';
      case '':
      case undefined:
      case null:
        return '未推送';
      default:
        return status;
    }
  }

  function pushTone(status) {
    if (status === 'sent') return 'badge badge-ok';
    if (status === 'failed') return 'badge badge-bad';
    return 'badge badge-warn';
  }

  function formatTime(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleString('zh-CN', { hour12: false });
  }

  function isExpired(message) {
    if (!message.expiresAt) return false;
    const time = new Date(message.expiresAt).getTime();
    return !Number.isNaN(time) && time <= Date.now();
  }

  async function api(path, options = {}) {
    const { method = 'GET', body, auth = true } = options;
    const headers = { Accept: 'application/json' };
    if (auth && state.token) headers.Authorization = `Bearer ${state.token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';

    let response;
    try {
      response = await fetch(path, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (error) {
      throw new Error(`网络错误：${error.message}`);
    }

    const text = await response.text();
    let payload = null;
    if (text) {
      try {
        payload = JSON.parse(text);
      } catch {
        payload = { raw: text };
      }
    }
    if (!response.ok) {
      const message =
        (payload && (payload.error || payload.message)) || `HTTP ${response.status}`;
      const error = new Error(message);
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  function describeError(error) {
    if (error.status === 401 || error.status === 403) {
      return `${error.message}（请检查管理员令牌）`;
    }
    return error.message || String(error);
  }

  // ---------- 令牌 ----------

  function refreshTokenState(text) {
    if (text) {
      $('token-state').textContent = text;
      return;
    }
    $('token-state').textContent = state.token
      ? '已加载（仅本标签页）'
      : '未设置';
  }

  $('token').value = state.token;
  refreshTokenState();

  $('save-token').addEventListener('click', () => {
    const value = $('token').value.trim();
    state.token = value;
    if (value) {
      sessionStorage.setItem(TOKEN_KEY, value);
      refreshTokenState('已保存到本标签页');
    } else {
      sessionStorage.removeItem(TOKEN_KEY);
      refreshTokenState('已清除');
    }
  });

  $('token').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      $('save-token').click();
    }
  });

  // ---------- Tab 切换 ----------

  function selectTab(name) {
    const send = name === 'send';
    $('tab-send').classList.toggle('active', send);
    $('tab-audit').classList.toggle('active', !send);
    $('tab-send').setAttribute('aria-selected', String(send));
    $('tab-audit').setAttribute('aria-selected', String(!send));
    $('pane-send').hidden = !send;
    $('pane-audit').hidden = send;
  }

  $('tab-send').addEventListener('click', () => selectTab('send'));
  $('tab-audit').addEventListener('click', () => selectTab('audit'));

  // ---------- 下发 ----------

  function parseData(raw) {
    const text = raw.trim();
    if (!text) return undefined;
    let value;
    try {
      value = JSON.parse(text);
    } catch {
      throw new Error('data 不是合法 JSON');
    }
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('data 必须是 JSON 对象');
    }
    return value;
  }

  async function submitSend(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);

    if (!state.token) {
      setStatus('send-state', '请先填写并保存管理员令牌', 'bad');
      return;
    }

    const userId = Number(data.get('userId'));
    const serverId = Number(data.get('serverId') || 0);
    const expiresRaw = String(data.get('expiresIn') || '').trim();

    if (!Number.isInteger(userId) || userId <= 0) {
      setStatus('send-state', '用户 ID 必须为正整数', 'bad');
      return;
    }

    let payload;
    try {
      payload = parseData(String(data.get('data') || ''));
    } catch (error) {
      setStatus('send-state', error.message, 'bad');
      return;
    }

    const request = {
      userId,
      kind: String(data.get('kind') || 'notice'),
      title: String(data.get('title') || '').trim(),
      body: String(data.get('body') || '').trim(),
    };
    if (serverId > 0) request.serverId = serverId;
    if (payload !== undefined) request.data = payload;
    if (expiresRaw) {
      const expires = Number(expiresRaw);
      if (!Number.isFinite(expires) || expires < 0) {
        setStatus('send-state', '过期秒数必须为非负整数', 'bad');
        return;
      }
      request.expiresIn = Math.floor(expires);
    }

    $('send-state').textContent = '发送中…';
    $('send-state').className = 'muted';
    try {
      const result = await api('/v1/messages', { method: 'POST', body: request });
      const message = (result && result.message) || {};
      const push = result && result.push;
      $('send-result').hidden = false;
      $('send-result').textContent = JSON.stringify(result, null, 2);
      setStatus(
        'send-state',
        `已发送 ${message.id || ''} · ${pushLabel(push)}`,
        push === 'sent' ? 'ok' : 'warn',
      );
    } catch (error) {
      setStatus('send-state', describeError(error), 'bad');
    }
  }

  $('send-form').addEventListener('submit', submitSend);

  // ---------- 审计 ----------

  function buildRow(message) {
    const row = el('tr');

    const timeCell = el('td');
    timeCell.append(el('div', 'mono', message.id || ''));
    timeCell.append(el('div', 'sub', formatTime(message.createdAt)));
    const kind = el('span', 'badge', message.kind || 'unknown');
    const kindWrap = el('div', 'sub');
    kindWrap.append(kind);
    timeCell.append(kindWrap);
    row.append(timeCell);

    const contentCell = el('td');
    const title = el(
      'div',
      'cell-title',
      message.title && String(message.title).trim()
        ? message.title
        : '（无标题）',
    );
    contentCell.append(title);
    if (message.body) {
      contentCell.append(el('div', 'cell-body', message.body));
    }
    const eventType =
      message.data && typeof message.data === 'object'
        ? message.data.eventType
        : undefined;
    if (eventType) {
      const badges = el('div', 'sub');
      badges.append(el('span', 'badge', String(eventType)));
      const success = message.data.success;
      if (success === true) {
        badges.append(el('span', 'badge badge-ok', 'success'));
      } else if (success === false) {
        badges.append(el('span', 'badge badge-bad', 'failure'));
      }
      contentCell.append(badges);
    }
    row.append(contentCell);

    row.append(el('td', null, message.source || '—'));

    const pushCell = el('td');
    pushCell.append(el('span', pushTone(message.pushStatus), pushLabel(message.pushStatus)));
    if (message.pushAttempts) {
      pushCell.append(el('div', 'sub', `尝试 ${message.pushAttempts} 次`));
    }
    if (message.pushedAt) {
      pushCell.append(el('div', 'sub', formatTime(message.pushedAt)));
    }
    row.append(pushCell);

    const deliveryCell = el('td');
    if (message.ackedAt) {
      deliveryCell.append(el('div', 'sub', `回执 ${formatTime(message.ackedAt)}`));
    } else {
      deliveryCell.append(el('div', 'sub', '未回执'));
    }
    if (message.revokedAt) {
      deliveryCell.append(el('span', 'badge badge-bad', '已撤回'));
    }
    if (isExpired(message)) {
      deliveryCell.append(el('span', 'badge badge-warn', '已过期'));
    }
    row.append(deliveryCell);

    const actions = el('td');
    const wrap = el('div', 'row-actions');

    const revoke = el('button', 'danger', '撤回');
    revoke.type = 'button';
    revoke.disabled = Boolean(message.revokedAt);
    revoke.addEventListener('click', () => revokeMessage(message));
    wrap.append(revoke);

    const resend = el('button', null, '重发');
    resend.type = 'button';
    resend.disabled = Boolean(message.revokedAt) || isExpired(message);
    resend.addEventListener('click', () => resendMessage(message));
    wrap.append(resend);

    actions.append(wrap);
    row.append(actions);

    return row;
  }

  function paintAudit() {
    const body = $('audit-body');
    body.replaceChildren(...state.loaded.map(buildRow));
    if (state.loaded.length === 0) {
      const row = el('tr');
      const cell = el('td', 'muted', '没有消息（或该用户还没有收件箱记录）');
      cell.colSpan = 6;
      row.append(cell);
      body.append(row);
    }
    $('load-more').hidden = !state.audit.cursor;
    setStatus(
      'audit-state',
      `已加载 ${state.loaded.length} 条${state.audit.cursor ? '，还有更多' : ''}`,
    );
  }

  async function fetchAudit(reset) {
    if (!state.token) {
      setStatus('audit-state', '请先填写并保存管理员令牌', 'bad');
      return;
    }
    if (reset) {
      state.loaded = [];
      state.audit.cursor = '';
    }

    const params = new URLSearchParams({
      userId: String(state.audit.userId),
      serverId: String(state.audit.serverId),
      limit: String(state.audit.limit),
    });
    if (state.audit.cursor) params.set('cursor', state.audit.cursor);

    setStatus('audit-state', '查询中…');
    try {
      const result = await api(`/v1/messages/audit?${params.toString()}`);
      const messages = (result && result.messages) || [];
      state.loaded = reset ? messages : state.loaded.concat(messages);
      state.audit.cursor = (result && result.nextCursor) || '';
      paintAudit();
    } catch (error) {
      setStatus('audit-state', describeError(error), 'bad');
    }
  }

  $('audit-form').addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const userId = Number(data.get('userId'));
    const serverId = Number(data.get('serverId') || 0);
    const limit = Number(data.get('limit') || 50);
    if (!Number.isInteger(userId) || userId <= 0) {
      setStatus('audit-state', '用户 ID 必须为正整数', 'bad');
      return;
    }
    state.audit.userId = userId;
    state.audit.serverId = serverId > 0 ? serverId : 1;
    state.audit.limit = Math.min(Math.max(Math.floor(limit) || 50, 1), 200);
    fetchAudit(true);
  });

  $('load-more').addEventListener('click', () => fetchAudit(false));

  function mergeMessage(updated) {
    if (!updated || !updated.id) return;
    const index = state.loaded.findIndex((item) => item.id === updated.id);
    if (index < 0) return;
    state.loaded[index] = Object.assign({}, state.loaded[index], updated, {
      userId: state.audit.userId,
      serverId: state.audit.serverId,
    });
    paintAudit();
  }

  async function revokeMessage(message) {
    const confirmed = window.confirm(
      `撤回消息 ${message.id}？\n撤回后 App 不再拉取，但审计记录会保留。`,
    );
    if (!confirmed) return;
    const params = new URLSearchParams({
      userId: String(state.audit.userId),
      serverId: String(state.audit.serverId),
    });
    try {
      const result = await api(
        `/v1/messages/${encodeURIComponent(message.id)}/revoke?${params.toString()}`,
        { method: 'POST' },
      );
      mergeMessage(result && result.message);
      setStatus('audit-state', `已撤回 ${message.id}`, 'ok');
    } catch (error) {
      setStatus('audit-state', describeError(error), 'bad');
    }
  }

  async function resendMessage(message) {
    const params = new URLSearchParams({
      userId: String(state.audit.userId),
      serverId: String(state.audit.serverId),
    });
    try {
      const result = await api(
        `/v1/messages/${encodeURIComponent(message.id)}/resend?${params.toString()}`,
        { method: 'POST' },
      );
      mergeMessage(result && result.message);
      const push = result && result.push;
      setStatus('audit-state', `已重发 ${message.id} · ${pushLabel(push)}`, 'ok');
    } catch (error) {
      setStatus('audit-state', describeError(error), 'bad');
    }
  }

  // 只读接口，不自动请求；避免页面一打开就需要令牌。
  refreshTokenState();
})();
