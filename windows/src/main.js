// Sky（Windows 版）主程序：管理 mihomo 核心、系統代理、托盤、更新檢查
const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, shell, clipboard, dialog, net, session } = require('electron');
const path = require('path');
const fs = require('fs');
const cp = require('child_process');
const crypto = require('crypto');
const config = require('./config');
const sysproxy = require('./sysproxy');

const IS_WIN = process.platform === 'win32';
const REPO = 'X1-1U/sky';                       // App 更新來源（GitHub Releases）
const CORE_REPO = 'MetaCubeX/mihomo';
const { PROXY_GROUP, AUTO_GROUP, LOCAL } = config;
const { ProfileText } = require('./profile');

// ---------- 單一實例 ----------
if (!process.env.SKY_HOME && !app.requestSingleInstanceLock()) { app.exit(0); process.exit(0); }

// ---------- 路徑 ----------
const workDir = process.env.SKY_HOME || path.join(app.getPath('appData'), IS_WIN ? 'Sky' : 'SkyElectron');
fs.mkdirSync(path.join(workDir, 'bin'), { recursive: true });
const configPath = path.join(workDir, 'config.yaml');
const logPath = path.join(workDir, 'core.log');
const statePath = path.join(workDir, 'state.json');
const pidPath = path.join(workDir, 'core.pid');
const coreName = IS_WIN ? 'mihomo.exe' : 'mihomo';
const updatedCore = path.join(workDir, 'bin', coreName);
const bundledCore = app.isPackaged
  ? path.join(process.resourcesPath, 'core', coreName)
  : path.join(__dirname, '..', 'vendor', IS_WIN ? 'mihomo.exe' : 'mihomo-darwin');
const coreBinary = () => (fs.existsSync(updatedCore) ? updatedCore : bundledCore);

// ---------- 設定 ----------
const DEFAULT_RULES = [
  ['DOMAIN-SUFFIX', 'local', '直連'], ['IP-CIDR', '127.0.0.0/8', '直連'], ['IP-CIDR', '10.0.0.0/8', '直連'],
  ['IP-CIDR', '172.16.0.0/12', '直連'], ['IP-CIDR', '192.168.0.0/16', '直連'], ['DOMAIN-SUFFIX', 'cn', '直連'],
].map(([type, payload, policy]) => ({ id: crypto.randomUUID(), type, payload, policy, enabled: true }));

function defaultStore() {
  return {
    subscriptions: [], rules: DEFAULT_RULES, localLinks: [], favorites: [],
    settings: {
      mixedPort: 7899, controllerPort: 9099, secret: crypto.randomBytes(16).toString('hex'),
      allowLan: false, autoConnect: false, logLevel: 'info', mode: 'rule', defaultPolicy: '代理',
      testURL: 'https://www.gstatic.com/generate_204', tun: false, autoCheckUpdates: true,
      ssidEnabled: false, ssidRules: [],
    },
  };
}

function loadStore() {
  const def = defaultStore();
  try {
    const s = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    return { ...def, ...s, settings: { ...def.settings, ...(s.settings || {}) } };
  } catch { return def; }
}
let store = loadStore();
const saveStore = () => fs.writeFileSync(statePath, JSON.stringify(store, null, 2));
saveStore();

// ---------- 執行狀態 ----------
const S = {
  coreReady: false, coreVersion: '', coreError: null, systemProxyOn: false, connectedSince: null,
  busy: false, proxies: {}, providers: {}, pausedConnections: false, testingDelay: false, updatingSubs: [], toast: null,
  mainGroup: PROXY_GROUP, profileId: null, currentSSID: null,
  isAdmin: false, tunActive: false, appUpdate: null, coreUpdate: null, checking: false, coreUpdating: false,
};
let connHistory = {};          // id → [{t, down, up}]
// 每秒變動的資料獨立傳給畫面（channel 'live'），避免整包狀態每秒重送、整頁重畫
const L = { down: 0, up: 0, history: [], connections: [], activeCount: 0 };
let lastTotals = null;
let lastConnBytes = {};
let watchConn = null;          // 連線頁正在看的那條
let coreProc = null;
let win = null;
let tray = null;
let toastTimer = null;
let quitting = false;

function toast(msg) {
  S.toast = msg;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { S.toast = null; push(); }, 2500);
  push();
}

function snapshot() {
  return {
    ...S, store, platform: process.platform, appVersion: app.getVersion(), workDir,
    subCounts: Object.fromEntries(store.subscriptions.map((x) => [x.id, subNodeCount(x)])),
  };
}
function liveSnapshot() { return { ...L, connHistory: watchConn ? (connHistory[watchConn] || []) : [] }; }
function push() { if (win && !win.isDestroyed()) win.webContents.send('state', snapshot()); updateTray(); }
function pushLive() { if (win && !win.isDestroyed() && win.isVisible()) win.webContents.send('live', liveSnapshot()); }

// ---------- mihomo API ----------
async function api(p, { method = 'GET', body, query, timeout = 10000 } = {}) {
  let url = `http://127.0.0.1:${store.settings.controllerPort}${p}`;
  if (query) url += '?' + new URLSearchParams(query).toString();
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${store.settings.secret}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeout),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${await res.text()}`);
  const t = await res.text();
  return t ? JSON.parse(t) : null;
}
const enc = encodeURIComponent;

// ---------- 核心 ----------
function useTun() { return store.settings.tun && (!IS_WIN || S.isAdmin); }

function writeConfig() {
  const b = config.build(store, workDir, { tun: useTun() });
  S.mainGroup = b.mainGroup;
  S.profileId = b.profile?.id || null;
  fs.writeFileSync(configPath, b.yaml);
  const r = cp.spawnSync(coreBinary(), ['-t', '-d', workDir, '-f', configPath], { encoding: 'utf8', windowsHide: true });
  if (r.error) return { ok: false, msg: '無法執行核心：' + r.error.message };
  if (r.status === 0) return { ok: true };
  const out = (r.stdout || '') + (r.stderr || '');
  const lines = out.split('\n').filter((l) => /rror|ERR|failed/.test(l)).slice(-3).join('\n');
  return { ok: false, msg: lines || out.slice(-400) };
}

function killStale() {
  try {
    const pid = parseInt(fs.readFileSync(pidPath, 'utf8'), 10);
    if (pid) {
      if (IS_WIN) cp.spawnSync('taskkill', ['/PID', String(pid), '/F'], { windowsHide: true });
      else { const c = cp.spawnSync('ps', ['-p', String(pid), '-o', 'comm='], { encoding: 'utf8' }); if (c.stdout.includes('mihomo')) process.kill(pid); }
    }
  } catch {}
  try { fs.unlinkSync(pidPath); } catch {}
}

function stopCore() {
  return new Promise((resolve) => {
    if (!coreProc) return resolve();
    const p = coreProc;
    coreProc = null;
    const timer = setTimeout(() => { try { p.kill('SIGKILL'); } catch {} resolve(); }, 2500);
    p.once('exit', () => { clearTimeout(timer); resolve(); });
    try { p.kill(); } catch { resolve(); }
    try { fs.unlinkSync(pidPath); } catch {}
  });
}

function tailLog(n = 200) {
  try { return fs.readFileSync(logPath, 'utf8').split('\n').slice(-n).join('\n'); } catch { return ''; }
}

async function startCore() {
  S.coreReady = false; S.coreError = null;
  const t = writeConfig();
  if (!t.ok) { S.coreError = '設定檔有誤：' + t.msg; push(); return; }
  const out = fs.openSync(logPath, 'w');
  coreProc = cp.spawn(coreBinary(), ['-d', workDir, '-f', configPath], { stdio: ['ignore', out, out], windowsHide: true });
  fs.writeFileSync(pidPath, String(coreProc.pid));
  const mine = coreProc;
  coreProc.on('exit', () => {
    if (coreProc === mine && !quitting) {
      coreProc = null; S.coreReady = false;
      S.coreError = '核心已停止：' + tailLog(3);
      setProxyForApp(false); push();
    }
  });
  for (let i = 0; i < 60; i++) {
    try { const v = await api('/version', { timeout: 800 }); S.coreVersion = v.version; S.coreReady = true; break; } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  if (!S.coreReady) { S.coreError = '核心沒有回應：' + tailLog(3); push(); return; }
  S.tunActive = useTun();
  try { await api(`/proxies/GLOBAL`, { method: 'PUT', body: { name: S.mainGroup } }); } catch {}
  lastTotals = null;
  setProxyForApp(true);
  await refreshProxies();
  refreshSubStatuses();
  push();
}

async function restartCore() {
  S.busy = true; push();
  await stopCore();
  await startCore();
  S.busy = false;
  if (S.systemProxyOn) await connect();
  toast(S.coreReady ? '核心已重新啟動' : '核心啟動失敗');
}

async function applyConfig() {
  S.busy = true; push();
  try {
    if (!S.coreReady || !coreProc) { await startCore(); return; }
    const t = writeConfig();
    if (!t.ok) { S.coreError = '設定檔有誤：' + t.msg; toast('設定檔有誤'); return; }
    // TUN 開關變了要整個重啟，熱重載不一定能正確建立／移除虛擬網卡
    if (S.tunActive !== useTun()) { await stopCore(); await startCore(); return; }
    try { await api('/configs', { method: 'PUT', query: { force: 'true' }, body: { path: configPath }, timeout: 60000 }); S.coreError = null; }
    catch (e) { S.coreError = '重新載入失敗：' + e.message; }
    try { await api(`/proxies/GLOBAL`, { method: 'PUT', body: { name: S.mainGroup } }); } catch {}
    await refreshProxies();
    refreshSubStatuses();
  } finally { S.busy = false; push(); }
}

/** 讓 App 自己對外的請求（檢查更新、下載核心）走 mihomo，GitHub 被擋時也能用 */
function setProxyForApp(on) {
  session.defaultSession.setProxy(on
    ? { proxyRules: `http://127.0.0.1:${store.settings.mixedPort}`, proxyBypassRules: '<local>' }
    : { mode: 'direct' }).catch(() => {});
}

// ---------- 系統代理 ----------
async function connect() {
  await sysproxy.enable(store.settings.mixedPort);
  S.systemProxyOn = true;
  if (!S.connectedSince) S.connectedSince = Date.now();
  push();
}
async function disconnect() {
  await sysproxy.disable();
  S.systemProxyOn = false; S.connectedSince = null;
  push();
}

// ---------- 定時更新 ----------
let lastProxySig = '';
/** 回傳 true 表示節點資料有變（需要通知畫面） */
async function refreshProxies() {
  if (!S.coreReady) return;
  let merged;
  try { merged = (await api('/proxies')).proxies; } catch { return; }
  try {
    S.providers = (await api('/providers/proxies')).providers;
    // /proxies 不含節點來源裡的節點；把它們（含延遲紀錄）合併進來
    nodeProvider = {};
    for (const [k, p] of Object.entries(S.providers)) {
      if (!['HTTP', 'File'].includes(p.vehicleType)) continue;
      for (const x of p.proxies || []) { nodeProvider[x.name] = k; if (!merged[x.name]) merged[x.name] = x; }
    }
  } catch {}
  const sig = JSON.stringify([merged, S.providers]);
  if (sig === lastProxySig) return false;
  lastProxySig = sig;
  S.proxies = merged;
  return true;
}

function startedAt(c) { return c.start ? Date.parse(c.start) || 0 : 0; }

async function tick() {
  if (!S.coreReady) return;
  let r;
  try { r = await api('/connections', { timeout: 3000 }); } catch { return; }
  const now = Date.now();
  if (lastTotals) {
    const dt = Math.max(0.2, (now - lastTotals.t) / 1000);
    L.down = Math.max(0, (r.downloadTotal - lastTotals.d) / dt);
    L.up = Math.max(0, (r.uploadTotal - lastTotals.u) / dt);
  }
  lastTotals = { t: now, d: r.downloadTotal, u: r.uploadTotal };
  L.history.push({ t: now, down: L.down, up: L.up });
  if (L.history.length > 300) L.history.splice(0, L.history.length - 300);

  const conns = r.connections || [];
  const nh = {}, nb = {};
  for (const c of conns) {
    const prev = lastConnBytes[c.id];
    const h = connHistory[c.id] || [];
    h.push({ t: now, down: prev ? Math.max(0, c.download - prev[0]) : 0, up: prev ? Math.max(0, c.upload - prev[1]) : 0 });
    if (h.length > 120) h.splice(0, h.length - 120);
    nh[c.id] = h; nb[c.id] = [c.download, c.upload];
  }
  connHistory = nh; lastConnBytes = nb;
  L.activeCount = conns.length;
  // ISO 時間字串可直接比較，不必每次比較都解析
  if (!S.pausedConnections) L.connections = conns.sort((a, b) => (b.start || '').localeCompare(a.start || ''));
}

function currentNode() {
  let n = S.proxies[S.mainGroup]?.now;
  for (let i = 0; i < 5 && n && S.proxies[n]?.now; i++) n = S.proxies[n].now;
  return n;
}

async function loop() {
  let n = 0;
  for (;;) {
    await tick();
    let changed = false;
    if (n % 5 === 0) changed = await refreshProxies();
    if (n % 60 === 30) { const c = currentNode(); if (c && c !== 'DIRECT') delay(c).catch(() => {}); }
    if (n % 60 === 45) autoUpdateSubscriptions();
    if (n % 300 === 20) refreshEmptyRuleProviders();
    if (n % 5 === 2) checkSSID().catch(() => {});
    n++;
    pushLive();                  // 每秒只送流量與連線
    if (changed) push();         // 節點資料有變才送完整狀態
    await new Promise((r) => setTimeout(r, 1000));
  }
}

let nodeProvider = {};
/** 節點來源裡的節點要用 /providers/proxies/{來源}/{節點}/healthcheck，/proxies/{節點}/delay 會 404 */
async function delay(name) {
  const prov = nodeProvider[name];
  const p = prov ? `/providers/proxies/${enc(prov)}/${enc(name)}/healthcheck` : `/proxies/${enc(name)}/delay`;
  try { await api(p, { query: { url: store.settings.testURL, timeout: '5000' }, timeout: 8000 }); } catch {}
}

const GROUP_TYPES = new Set(['Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay']);

/** 規則集第一次下載失敗時主動補抓（mihomo 預設要等更新間隔才重試） */
async function refreshEmptyRuleProviders() {
  if (!S.coreReady) return;
  let provs; try { provs = (await api('/providers/rules')).providers || {}; } catch { return; }
  await Promise.all(Object.entries(provs).filter(([, p]) => !p.ruleCount).map(([n]) =>
    api(`/providers/rules/${enc(n)}`, { method: 'PUT', timeout: 30000 }).catch(() => {})));
}

const inlineCache = {};
function subNodeCount(sub) {
  const file = config.subFile(sub, workDir);
  if (!fs.existsSync(file)) return null;
  if (sub.id === S.profileId) {
    const ours = new Set(store.subscriptions.map(config.providerName).concat([LOCAL, 'default']));
    const fromProviders = Object.values(S.providers).filter((p) => !ours.has(p.name) && ['HTTP', 'File'].includes(p.vehicleType)).reduce((a, p) => a + (p.proxies?.length || 0), 0);
    const key = sub.id + '|' + (sub.updatedAt || 0);
    if (!(key in inlineCache)) { try { inlineCache[key] = new ProfileText(fs.readFileSync(file, 'utf8')).inlineProxyCount; } catch { inlineCache[key] = 0; } }
    const inline = inlineCache[key];
    return inline + fromProviders;
  }
  return S.providers[config.providerName(sub)]?.proxies?.length ?? null;
}

function refreshSubStatuses() {
  let changed = false;
  for (const s of store.subscriptions) {
    if (!s.enabled || s.statusOK != null) continue;
    const ok = (subNodeCount(s) || 0) > 0;
    s.statusOK = ok; s.statusMessage = ok ? '更新成功' : '還沒有節點'; changed = true;
  }
  if (changed) saveStore();
}

/** 舊版把訂閱存在 providers/，搬到 subs/；順便判斷是不是完整設定檔 */
function migrateSubscriptions() {
  fs.mkdirSync(path.join(workDir, 'subs'), { recursive: true });
  for (const s of store.subscriptions) {
    if (s.useProfile === undefined) s.useProfile = true;
    const dst = config.subFile(s, workDir);
    const old = path.join(workDir, 'providers', config.providerName(s) + '.yaml');
    if (!fs.existsSync(dst) && fs.existsSync(old)) { fs.renameSync(old, dst); s.updatedAt = s.updatedAt || fs.statSync(dst).mtimeMs; }
    try { s.isProfile = new ProfileText(fs.readFileSync(dst, 'utf8')).isFullProfile; } catch {}
  }
  saveStore();
}

async function downloadSub(sub) {
  const url = String(sub.url || '').trim();
  if (!/^https?:\/\//i.test(url)) throw new Error('連結格式不對');
  const viaProxy = sub.viaProxy && S.coreReady && currentNode() && currentNode() !== 'DIRECT';
  const headers = { 'User-Agent': `clash.meta mihomo/${S.coreVersion || '1.19'}` };
  // 走代理用 Electron 的 net.fetch（已設定成 mihomo），直連用 Node 的 fetch
  const res = viaProxy ? await net.fetch(url, { headers }) : await fetch(url, { headers, signal: AbortSignal.timeout(30000) });
  if (!res.ok) throw new Error('伺服器回應 HTTP ' + res.status);
  const text = await res.text();
  if (!text.trim()) throw new Error('內容是空的');
  return { text, info: res.headers.get('subscription-userinfo') };
}

async function updateSubscription(id, { apply = true } = {}) {
  const sub = store.subscriptions.find((s) => s.id === id);
  if (!sub || !sub.url || S.updatingSubs.includes(id)) return;
  S.updatingSubs = [...S.updatingSubs, id]; push();
  try {
    const { text, info } = await downloadSub(sub);
    const file = config.subFile(sub, workDir);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
    sub.isProfile = new ProfileText(text).isFullProfile;
    sub.updatedAt = Date.now();
    if (info) {
      const kv = {};
      for (const part of info.split(';')) { const [k, v] = part.split('=').map((x) => x.trim()); if (k && v) kv[k.toLowerCase()] = Math.round(Number(v)); }
      Object.assign(sub, { upload: kv.upload, download: kv.download, total: kv.total, expire: kv.expire });
    }
    saveStore();
    if (apply) await applyConfig();
    const count = subNodeCount(sub) || 0;
    sub.statusOK = true;
    sub.statusMessage = sub.isProfile ? '更新成功（完整設定檔）' : (count ? `更新成功，${count} 個節點` : '更新成功');
  } catch (e) {
    sub.statusOK = false; sub.statusMessage = '更新失敗：' + e.message;
  } finally {
    saveStore();
    S.updatingSubs = S.updatingSubs.filter((x) => x !== id); push();
  }
}

function autoUpdateSubscriptions() {
  const now = Date.now();
  for (const s of store.subscriptions) {
    if (!s.enabled || !s.url) continue;
    const missing = !fs.existsSync(config.subFile(s, workDir));
    const due = s.autoUpdate && now - (s.updatedAt || 0) > Math.max(1, s.intervalHours || 6) * 3600000;
    if (missing || due) updateSubscription(s.id);
  }
}

function profileInfo(id) {
  const sub = store.subscriptions.find((s) => s.id === id);
  if (!sub) return { groups: [], rules: [] };
  try { const p = new ProfileText(fs.readFileSync(config.subFile(sub, workDir), 'utf8')); return { groups: p.groupNames(), rules: p.rules() }; }
  catch { return { groups: [], rules: [] }; }
}

// ---------- Wi-Fi 自動切換 ----------
let ssidSaved = null;   // 進入指定 Wi-Fi 前的 { mode, proxy }
async function readSSID() {
  if (!IS_WIN) return null;
  const { out } = await sysproxy.run('netsh', ['wlan', 'show', 'interfaces']);
  const m = out.split(/\r?\n/).map((l) => l.match(/^\s*SSID\s*:\s*(.+)$/)).find(Boolean);
  return m ? m[1].trim() : null;
}
const SSID_ACTIONS = { direct: '切到直連模式', rule: '切到規則模式', global: '切到全域模式', disconnect: '中斷系統代理' };
async function checkSSID(force = false) {
  if (!store.settings.ssidEnabled) return;
  const now = await readSSID();
  if (!force && now === S.currentSSID) return;
  S.currentSSID = now;
  const rule = now && (store.settings.ssidRules || []).find((r) => r.ssid === now);
  if (rule) {
    if (!ssidSaved) ssidSaved = { mode: store.settings.mode, proxy: S.systemProxyOn };
    if (rule.action === 'disconnect') { if (S.systemProxyOn) await disconnect(); }
    else if (store.settings.mode !== rule.action) await act.setMode(rule.action);
    toast(`Wi-Fi「${now}」：${SSID_ACTIONS[rule.action]}`);
  } else if (ssidSaved) {
    const sv = ssidSaved; ssidSaved = null;
    if (store.settings.mode !== sv.mode) await act.setMode(sv.mode);
    if (sv.proxy && !S.systemProxyOn) await connect();
    toast('已離開指定的 Wi-Fi，恢復原本設定');
  }
  push();
}

// ---------- 節點詳情（從訂閱檔找伺服器與連接埠） ----------
function readProviderText(file) {
  let s;
  try { s = fs.readFileSync(file, 'utf8'); } catch { return null; }
  if (!s.includes('proxies:') && !s.includes('://')) {
    try { const d = Buffer.from(s.trim(), 'base64').toString('utf8'); if (d.includes('://')) s = d; } catch {}
  }
  return s;
}

function nodeDetail(name) {
  let file = null;
  for (const [k, p] of Object.entries(S.providers)) {
    if (!['HTTP', 'File'].includes(p.vehicleType) || !(p.proxies || []).some((x) => x.name === name)) continue;
    if (k.startsWith('sub-') || k === LOCAL) file = config.providerFile(k, workDir);
    else if (fs.existsSync(path.join(workDir, 'proxies', k + '.yaml'))) file = path.join(workDir, 'proxies', k + '.yaml');
    break;
  }
  if (!file) { const prof = store.subscriptions.find((x) => x.id === S.profileId); if (prof) file = config.subFile(prof, workDir); }
  if (!file) return null;
  const text = readProviderText(file);
  if (!text) return null;
  if (text.includes('://') && !text.includes('proxies:')) {
    for (const line of text.split(/\r?\n/)) {
      if (line.startsWith('vmess://')) {
        try { const j = JSON.parse(Buffer.from(line.slice(8), 'base64').toString('utf8')); if (j.ps === name) return { server: j.add, port: String(j.port) }; } catch {}
        continue;
      }
      const h = line.lastIndexOf('#');
      if (h < 0) continue;
      let n; try { n = decodeURIComponent(line.slice(h + 1)); } catch { n = line.slice(h + 1); }
      if (n !== name) continue;
      try { const u = new URL(line.slice(0, h)); return { server: u.hostname, port: u.port || '—' }; } catch { return null; }
    }
    return null;
  }
  const lines = text.split(/\r?\n/);
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`name:\\s*["']?${esc}["']?\\s*(,|}|$)`);
  const idx = lines.findIndex((l) => re.test(l));
  if (idx < 0) return null;
  const grab = (key, s) => { const m = s.match(new RegExp(`${key}:\\s*"?([^,}"\\s]+)`)); return m ? m[1] : null; };
  if (grab('server', lines[idx])) return { server: grab('server', lines[idx]), port: grab('port', lines[idx]) || '—' };
  let a = idx; while (a > 0 && !lines[a].trim().startsWith('-')) a--;
  let b = idx + 1; while (b < lines.length && !lines[b].trim().startsWith('-')) b++;
  const block = lines.slice(a, b).join('\n');
  const srv = grab('server', block);
  return srv ? { server: srv, port: grab('port', block) || '—' } : null;
}

// ---------- 連線的 App 圖示 ----------
const iconCache = {};
async function processIcon(p) {
  if (!p) return null;
  if (iconCache[p] !== undefined) return iconCache[p];
  let target = p;
  if (!IS_WIN) { const m = p.match(/^(.*?\.app)\//); if (m) target = m[1]; }
  try { iconCache[p] = (await app.getFileIcon(target, { size: 'normal' })).toDataURL(); } catch { iconCache[p] = null; }
  return iconCache[p];
}

// ---------- 更新檢查 ----------
function cmpVersion(a, b) {
  const pa = String(a).replace(/^v/, '').split(/[.-]/).map((x) => parseInt(x, 10) || 0);
  const pb = String(b).replace(/^v/, '').split(/[.-]/).map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
  }
  return 0;
}

async function githubLatest(repo) {
  const res = await net.fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'Sky-Updater' },
  });
  if (res.status === 404) throw new Error('找不到發佈版本');
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return res.json();
}

async function checkUpdates({ silent = false } = {}) {
  S.checking = true; push();
  const errors = [];
  try {
    try {
      const rel = await githubLatest(REPO);
      if (cmpVersion(rel.tag_name, app.getVersion()) > 0) {
        const asset = (rel.assets || []).find((a) => IS_WIN ? /\.exe$/i.test(a.name) : /mac.*\.zip$/i.test(a.name));
        S.appUpdate = { version: rel.tag_name, notes: rel.body || '', url: asset?.browser_download_url || rel.html_url, page: rel.html_url };
      } else S.appUpdate = null;
    } catch (e) { errors.push('App：' + e.message); }
    try {
      const rel = await githubLatest(CORE_REPO);
      const want = IS_WIN ? `mihomo-windows-amd64-compatible-${rel.tag_name}.zip` : `mihomo-darwin-arm64-${rel.tag_name}.gz`;
      const asset = (rel.assets || []).find((a) => a.name === want);
      if (S.coreVersion && cmpVersion(rel.tag_name, S.coreVersion) > 0 && asset) {
        S.coreUpdate = { version: rel.tag_name, url: asset.browser_download_url, name: asset.name };
      } else S.coreUpdate = null;
    } catch (e) { errors.push('mihomo：' + e.message); }
  } finally {
    S.checking = false;
    store.settings.lastUpdateCheck = Date.now(); saveStore();
    push();
  }
  if (!silent) {
    if (errors.length && !S.appUpdate && !S.coreUpdate) toast('檢查更新失敗：' + errors[0]);
    else if (!S.appUpdate && !S.coreUpdate) toast('已經是最新版本');
  }
}

async function updateCore() {
  const u = S.coreUpdate;
  if (!u || S.coreUpdating) return;
  S.coreUpdating = true; push();
  const tmp = path.join(workDir, 'bin', 'download');
  try {
    fs.rmSync(tmp, { recursive: true, force: true });
    fs.mkdirSync(tmp, { recursive: true });
    const res = await net.fetch(u.url);
    if (!res.ok) throw new Error('下載失敗 HTTP ' + res.status);
    const archive = path.join(tmp, u.name);
    fs.writeFileSync(archive, Buffer.from(await res.arrayBuffer()));
    let exe;
    if (IS_WIN) {
      const r = cp.spawnSync('powershell.exe', ['-NoProfile', '-Command', `Expand-Archive -Force -LiteralPath '${archive}' -DestinationPath '${tmp}'`], { windowsHide: true });
      if (r.status !== 0) throw new Error('解壓縮失敗');
      exe = fs.readdirSync(tmp).map((f) => path.join(tmp, f)).find((f) => f.endsWith('.exe'));
    } else {
      exe = path.join(tmp, 'mihomo');
      fs.writeFileSync(exe, require('zlib').gunzipSync(fs.readFileSync(archive)));
      fs.chmodSync(exe, 0o755);
    }
    if (!exe) throw new Error('壓縮檔裡找不到核心');
    const v = cp.spawnSync(exe, ['-v'], { encoding: 'utf8', windowsHide: true });
    if (v.status !== 0 || !/Mihomo/i.test(v.stdout)) throw new Error('新核心無法執行');
    await stopCore();
    fs.copyFileSync(exe, updatedCore);
    if (!IS_WIN) fs.chmodSync(updatedCore, 0o755);
    await startCore();
    if (S.systemProxyOn) await connect();
    S.coreUpdate = null;
    toast(`mihomo 已更新到 ${S.coreVersion}`);
  } catch (e) {
    toast('更新核心失敗：' + e.message);
    if (!coreProc) await startCore();
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
    S.coreUpdating = false; push();
  }
}

// ---------- TUN ----------
async function relaunchAsAdmin() {
  // 先結束自己（釋放單一實例鎖），再由 PowerShell 以系統管理員身分重新開啟
  const exe = process.execPath.replace(/'/g, "''");
  const args = app.isPackaged ? '' : ` -ArgumentList '${app.getAppPath().replace(/'/g, "''")}'`;
  const child = cp.spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command',
    `Start-Sleep -Seconds 2; Start-Process -FilePath '${exe}'${args} -Verb RunAs`], { detached: true, stdio: 'ignore', windowsHide: true });
  child.unref();
  app.quit();
}

async function setTun(on) {
  if (on && IS_WIN && !S.isAdmin) {
    const r = await dialog.showMessageBox(win, {
      type: 'question', buttons: ['以系統管理員身分重新啟動', '取消'], defaultId: 0, cancelId: 1,
      title: '需要系統管理員權限',
      message: 'TUN 模式需要系統管理員權限',
      detail: 'Sky 會關閉並以系統管理員身分重新開啟，Windows 會跳出確認視窗。重新開啟後 TUN 會自動啟用。',
    });
    if (r.response !== 0) { push(); return; }
    store.settings.tun = true; store.settings.resumeConnect = S.systemProxyOn; saveStore();
    await relaunchAsAdmin();
    return;
  }
  store.settings.tun = on; saveStore();
  await applyConfig();
  toast(on ? (S.tunActive ? 'TUN 模式已開啟' : 'TUN 開啟失敗') : 'TUN 模式已關閉');
}

// ---------- 視窗與托盤 ----------
function createWindow() {
  win = new BrowserWindow({
    width: 1320, height: 860, minWidth: 1200, minHeight: 780,
    backgroundColor: '#16171B', title: 'Sky', show: false,
    icon: path.join(__dirname, '..', 'build', 'icon.png'),
    titleBarStyle: 'hidden',
    titleBarOverlay: IS_WIN ? { color: '#16171B', symbolColor: '#E8EAED', height: 40 } : undefined,
    trafficLightPosition: { x: 18, y: 18 },
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  win.removeMenu();
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'), { query: { page: process.env.SKY_PAGE || 'overview' } });
  win.once('ready-to-show', () => win.show());
  win.webContents.on('console-message', (_e, level, message, line, source) => { if (level >= 2) console.error(`[畫面] ${message} (${source}:${line})`); });
  win.on('close', (e) => { if (!quitting) { e.preventDefault(); win.hide(); } });
}

function showWindow() { if (!win) createWindow(); win.show(); win.focus(); }

function updateTray() {
  if (!tray) return;
  const g = S.proxies[S.mainGroup];
  const nodeItems = (g?.all || []).slice(0, 60).map((n) => ({ label: n, type: 'radio', checked: n === g.now, click: () => act.select(n, S.mainGroup) }));
  const menu = Menu.buildFromTemplate([
    { label: S.coreReady ? (S.systemProxyOn ? 'Sky · 已連線' : 'Sky · 未連線') : 'Sky · 核心未執行', enabled: false },
    { type: 'separator' },
    { label: '系統代理', type: 'checkbox', checked: S.systemProxyOn, enabled: S.coreReady, click: () => act.toggleConnection() },
    { label: 'TUN 模式', type: 'checkbox', checked: !!store.settings.tun, enabled: S.coreReady, click: (i) => setTun(i.checked) },
    { label: '路由模式', submenu: [['rule', '規則'], ['global', '全域'], ['direct', '直連']].map(([m, l]) => ({ label: l, type: 'radio', checked: store.settings.mode === m, click: () => act.setMode(m) })) },
    { label: '節點：' + (currentNode() || '未選擇'), submenu: nodeItems.length ? nodeItems : [{ label: '沒有節點', enabled: false }] },
    { type: 'separator' },
    { label: '打開主視窗', click: showWindow },
    { label: '複製終端代理命令', click: () => act.copyTerminal() },
    { type: 'separator' },
    { label: '結束 Sky', click: () => app.quit() },
  ]);
  tray.setContextMenu(menu);
  tray.setToolTip(S.systemProxyOn ? 'Sky：已連線' : 'Sky：未連線');
}

function createTray() {
  const img = nativeImage.createFromPath(path.join(__dirname, '..', 'build', IS_WIN ? 'tray.png' : 'trayTemplate.png'));
  tray = new Tray(img.isEmpty() ? nativeImage.createEmpty() : img);
  tray.on('click', showWindow);
  updateTray();
}

// ---------- 給畫面呼叫的動作 ----------
const terminalCommand = () => {
  const p = store.settings.mixedPort;
  return IS_WIN
    ? `set http_proxy=http://127.0.0.1:${p} & set https_proxy=http://127.0.0.1:${p}`
    : `export https_proxy=http://127.0.0.1:${p} http_proxy=http://127.0.0.1:${p} all_proxy=socks5://127.0.0.1:${p}`;
};

const act = {
  async toggleConnection() { S.systemProxyOn ? await disconnect() : await connect(); },
  async setMode(m) {
    store.settings.mode = m; saveStore(); push();
    try { await api('/configs', { method: 'PATCH', body: { mode: m } }); await api('/connections', { method: 'DELETE' }); } catch {}
  },
  async select(name, group) {
    const g = group || S.mainGroup;
    try {
      await api(`/proxies/${enc(g)}`, { method: 'PUT', body: { name } });
      try { await api('/connections', { method: 'DELETE' }); } catch {}
      await refreshProxies();
      toast(`${g} → ${name.replace(/^[\u{1F1E6}-\u{1F1FF}]{2}\s*/u, '')}`);
      refreshEmptyRuleProviders();
    } catch (e) { toast('切換失敗：' + e.message); }
  },
  async testGroup(group) {
    if (S.testingDelay) return;
    S.testingDelay = true; push();
    try { await api(`/group/${enc(group || S.mainGroup)}/delay`, { query: { url: store.settings.testURL, timeout: '5000' }, timeout: 30000 }); } catch {}
    await refreshProxies();
    S.testingDelay = false; toast('延遲測試完成');
  },
  profileInfo,
  async enableSSID(on) { store.settings.ssidEnabled = on; saveStore(); if (on) await checkSSID(true); else { S.currentSSID = null; push(); } },
  async addSSIDRule(ssid, action) {
    const name = String(ssid).trim(); if (!name) return;
    store.settings.ssidRules = (store.settings.ssidRules || []).filter((r) => r.ssid !== name).concat([{ id: crypto.randomUUID(), ssid: name, action }]);
    saveStore(); await checkSSID(true);
  },
  async setSSIDAction(id, action) { const r = (store.settings.ssidRules || []).find((x) => x.id === id); if (r) { r.action = action; saveStore(); await checkSSID(true); } },
  async removeSSIDRule(id) { store.settings.ssidRules = (store.settings.ssidRules || []).filter((r) => r.id !== id); saveStore(); await checkSSID(true); },
  async testOne(name) { await delay(name); await refreshProxies(); push(); },
  toggleFavorite(name) {
    const i = store.favorites.indexOf(name);
    if (i >= 0) store.favorites.splice(i, 1); else store.favorites.push(name);
    saveStore(); push();
  },
  async addLinks(text) {
    const lines = String(text).split(/\r?\n/).map((l) => l.trim()).filter((l) => l.includes('://'));
    if (!lines.length) return toast('沒有找到節點連結');
    store.localLinks.push(...lines); saveStore();
    await applyConfig(); toast(`已新增 ${lines.length} 個節點`);
  },
  async setLocalLink(index, text) {
    if (index < 0 || index >= store.localLinks.length) return;
    if (!String(text).trim()) store.localLinks.splice(index, 1); else store.localLinks[index] = String(text).trim();
    saveStore(); await applyConfig();
  },
  async saveSubscription(sub) {
    const i = store.subscriptions.findIndex((s) => s.id === sub.id);
    const old = i >= 0 ? store.subscriptions[i] : null;
    const clean = { ...sub, url: String(sub.url || '').trim(), name: String(sub.name || '').trim() || '未命名訂閱' };
    const urlChanged = !old || old.url !== clean.url;
    if (old) {
      for (const k of ['statusOK', 'statusMessage', 'isProfile', 'updatedAt', 'upload', 'download', 'total', 'expire']) clean[k] = old[k];
      store.subscriptions[i] = clean;
    } else store.subscriptions.push(clean);
    saveStore();
    toast('已儲存');
    if (urlChanged) { try { fs.unlinkSync(config.subFile(clean, workDir)); } catch {} if (clean.url) await updateSubscription(clean.id); }
    else await applyConfig();
  },
  newSubscription() {
    const s = { id: crypto.randomUUID(), name: `新訂閱 ${store.subscriptions.length + 1}`, url: '', enabled: true, autoUpdate: true, intervalHours: 6, viaProxy: true, useProfile: true };
    store.subscriptions.push(s); saveStore(); push();
    return s.id;
  },
  async setSubEnabled(id, on) {
    const s = store.subscriptions.find((x) => x.id === id);
    if (!s) return;
    s.enabled = on; saveStore(); await applyConfig();
  },
  async deleteSubscription(id) {
    const s = store.subscriptions.find((x) => x.id === id);
    if (!s) return;
    store.subscriptions = store.subscriptions.filter((x) => x.id !== id);
    try { fs.unlinkSync(config.subFile(s, workDir)); } catch {}
    saveStore(); await applyConfig();
  },
  updateSubscription: (id) => updateSubscription(id),
  updateAll() { for (const s of store.subscriptions) if (s.enabled && s.url) updateSubscription(s.id); },
  subNodeCounts() { return Object.fromEntries(store.subscriptions.map((s) => [s.id, subNodeCount(s)])); },
  async setRules(rules) { store.rules = rules; saveStore(); await applyConfig(); },
  async setDefaultPolicy(p) { store.settings.defaultPolicy = p; saveStore(); await applyConfig(); },
  async closeConnection(id) { try { await api(`/connections/${enc(id)}`, { method: 'DELETE' }); } catch {} },
  async closeAll() { try { await api('/connections', { method: 'DELETE' }); } catch {} toast('已中斷全部連線'); },
  setPaused(v) { S.pausedConnections = v; push(); pushLive(); },
  watchConnection(id) { watchConn = id; pushLive(); },
  copyTerminal() { clipboard.writeText(terminalCommand()); toast('已複製終端代理命令'); },
  copyText(t) { clipboard.writeText(String(t)); toast('已複製'); },
  async setSettings(patch) {
    const before = { ...store.settings };
    Object.assign(store.settings, patch); saveStore();
    if (patch.controllerPort && patch.controllerPort !== before.controllerPort) await restartCore();
    else if (['mixedPort', 'allowLan', 'logLevel', 'testURL'].some((k) => k in patch)) await applyConfig();
    if (patch.mixedPort && patch.mixedPort !== before.mixedPort && S.systemProxyOn) { await connect(); setProxyForApp(true); }
    push();
  },
  setLaunchAtLogin(on) { app.setLoginItemSettings({ openAtLogin: on }); push(); },
  launchAtLogin() { return app.getLoginItemSettings().openAtLogin; },
  restartCore,
  setTun,
  openWorkDir() { shell.openPath(workDir); },
  tailLog,
  nodeDetail,
  processIcon,
  checkUpdates: () => checkUpdates({ silent: false }),
  updateCore,
  openURL(u) { if (/^https:\/\//.test(u)) shell.openExternal(u); },
  terminalCommand,
};

ipcMain.handle('act', async (_e, name, ...args) => {
  if (typeof act[name] !== 'function') throw new Error('unknown action ' + name);
  return act[name](...args);
});
ipcMain.handle('snapshot', () => snapshot());

// ---------- 生命週期 ----------
app.on('second-instance', showWindow);
// macOS 點 Dock 圖示、或重新開啟 App 時顯示主視窗
app.on('activate', showWindow);

app.whenReady().then(async () => {
  app.setAppUserModelId('com.onsunday.sky');
  S.isAdmin = await sysproxy.isAdmin();
  createWindow();
  createTray();
  killStale();
  migrateSubscriptions();
  await startCore();
  loop();
  autoUpdateSubscriptions();
  if (store.settings.ssidEnabled) checkSSID(true).catch(() => {});
  if (store.settings.tun && IS_WIN && !S.isAdmin) toast('TUN 需要系統管理員權限，這次未啟用');
  const pointing = await sysproxy.isPointing(store.settings.mixedPort);
  if (store.settings.autoConnect || pointing || store.settings.resumeConnect) {
    store.settings.resumeConnect = false; saveStore();
    await connect();
  }
  // 每天自動檢查一次更新
  if (store.settings.autoCheckUpdates && Date.now() - (store.settings.lastUpdateCheck || 0) > 86400000) {
    setTimeout(() => checkUpdates({ silent: true }), 8000);
  }
});

app.on('window-all-closed', (e) => e.preventDefault?.());

let cleaned = false;
app.on('before-quit', async (e) => {
  quitting = true;
  if (cleaned) return;
  e.preventDefault();
  try { if (S.systemProxyOn) await sysproxy.disable(); } catch {}
  await stopCore();
  cleaned = true;
  app.quit();
});
