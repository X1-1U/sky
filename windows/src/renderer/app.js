import { html, render, useState, useEffect, useRef } from '../../node_modules/htm/preact/standalone.module.js';

const sky = window.sky;
const act = (name, ...a) => sky.act(name, ...a);
const PROXY_GROUP = '代理', AUTO_GROUP = '自動選擇', LOCAL = 'local';
const POLICIES = ['代理', '直連', '拒絕', '自動選擇'];
const RULE_TYPES = ['DOMAIN-SUFFIX', 'DOMAIN', 'DOMAIN-KEYWORD', 'DOMAIN-REGEX', 'IP-CIDR', 'IP-CIDR6', 'SRC-IP-CIDR', 'DST-PORT', 'PROCESS-NAME', 'GEOIP', 'GEOSITE'];

// ---------- 圖示（線條 SVG） ----------
const P = {
  home: 'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z',
  server: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
  layers: 'm12 3 9 5-9 5-9-5 9-5zM3 13l9 5 9-5M3 17.5 12 22l9-4.5',
  sliders: 'M4 7h9M17 7h3M4 17h3M11 17h9M15 5v4M9 15v4',
  pulse: 'M3 12h4l3-7 4 14 3-7h4',
  gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  swap: 'M7 7h13M16 3l4 4-4 4M17 17H4M8 13l-4 4 4 4',
  down: 'M12 4v12M6 11l6 6 6-6M5 21h14',
  up: 'M12 20V8M6 13l6-6 6 6M5 3h14',
  clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
  link: 'M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.5 1.5M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.5-1.5',
  search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-3.5-3.5',
  plus: 'M12 5v14M5 12h14',
  refresh: 'M20 11a8 8 0 0 0-14.9-3M4 4v4h4M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4',
  gauge: 'M12 21a9 9 0 1 1 0-18 9 9 0 0 1 0 18zM12 12l4-3M7 15h.01M17 15h.01',
  star: 'm12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  chevR: 'm9 6 6 6-6 6',
  check: 'M5 12l5 5 9-10',
  eye: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  eyeOff: 'M3 3l18 18M10.6 10.6a3 3 0 0 0 4.2 4.2M9.9 5.1A9.8 9.8 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.1M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6',
  info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 11v5M12 8h.01',
  import: 'M12 3v12M7 10l5 5 5-5M4 17v3h16v-3',
  grip: 'M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01',
  lock: 'M6 11h12v10H6zM8 11V7a4 4 0 0 1 8 0v4',
  pause: 'M8 5v14M16 5v14',
  play: 'M7 4l13 8-13 8z',
  x: 'M18 6 6 18M6 6l12 12',
  proxy: 'M12 5a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM5 21a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM19 21a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM12 5v5M12 10l-6 7M12 10l6 7',
  arrowR: 'M4 12h16M14 6l6 6-6 6',
  ban: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM5.6 5.6l12.8 12.8',
  bolt: 'M13 2 4 14h7l-1 8 9-12h-7z',
  pencil: 'M4 20h4L19 9l-4-4L4 16zM14 6l4 4',
  app: 'M4 4h16v16H4z',
  shield: 'M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z',
  cloud: 'M7 18a5 5 0 1 1 1-9.9A6 6 0 0 1 19 10a4 4 0 0 1 0 8z',
};
const I = (name, extra = '') => html`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class=${extra} aria-hidden="true"><path d=${P[name]} /></svg>`;
const POLICY_ICON = { '代理': 'proxy', '直連': 'arrowR', '拒絕': 'ban', '自動選擇': 'bolt' };

// ---------- 格式 ----------
const fmtBytes = (b) => {
  const u = ['B', 'KB', 'MB', 'GB', 'TB']; let v = Math.max(0, b || 0), i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return i === 0 ? `${Math.round(v)} B` : `${v >= 100 ? v.toFixed(0) : v.toFixed(1)} ${u[i]}`;
};
const fmtSpeed = (b) => fmtBytes(b) + '/s';
const fmtDur = (ms) => { const t = Math.max(0, Math.floor(ms / 1000)); const p = (n) => String(n).padStart(2, '0'); return `${p(Math.floor(t / 3600))}:${p(Math.floor(t / 60) % 60)}:${p(t % 60)}`; };
const fmtDelay = (d) => d == null ? '—' : d === 0 ? '逾時' : `${d} ms`;
const parseDate = (s) => { const t = Date.parse(s); return isNaN(t) || t < 946684800000 ? null : t; };
const ago = (t) => { if (!t) return '尚未更新'; const s = (Date.now() - t) / 1000; if (s < 60) return '剛剛'; if (s < 3600) return `${Math.floor(s / 60)} 分鐘前`; if (s < 86400) return `${Math.floor(s / 3600)} 小時前`; return `${Math.floor(s / 86400)} 天前`; };
const hms = (t) => new Date(t).toTimeString().slice(0, 8);
const hm = (t) => new Date(t).toTimeString().slice(0, 5);

// ---------- 國旗 ----------
const FLAG_TABLE = [['香港', 'HK'], ['Hong Kong', 'HK'], ['台灣', 'TW'], ['臺灣', 'TW'], ['台湾', 'TW'], ['Taiwan', 'TW'], ['日本', 'JP'], ['東京', 'JP'], ['东京', 'JP'], ['大阪', 'JP'], ['Japan', 'JP'],
  ['新加坡', 'SG'], ['狮城', 'SG'], ['獅城', 'SG'], ['Singapore', 'SG'], ['美國', 'US'], ['美国', 'US'], ['洛杉磯', 'US'], ['洛杉矶', 'US'], ['United States', 'US'], ['韓國', 'KR'], ['韩国', 'KR'], ['Korea', 'KR'],
  ['英國', 'GB'], ['英国', 'GB'], ['德國', 'DE'], ['德国', 'DE'], ['法國', 'FR'], ['法国', 'FR'], ['加拿大', 'CA'], ['澳洲', 'AU'], ['澳大利亚', 'AU'], ['俄羅斯', 'RU'], ['俄罗斯', 'RU'], ['印度', 'IN'],
  ['土耳其', 'TR'], ['荷蘭', 'NL'], ['荷兰', 'NL'], ['泰國', 'TH'], ['泰国', 'TH'], ['越南', 'VN'], ['馬來', 'MY'], ['马来', 'MY'], ['菲律賓', 'PH'], ['菲律宾', 'PH'], ['澳門', 'MO'], ['澳门', 'MO'], ['阿根廷', 'AR'], ['巴西', 'BR']];
function flagCode(name = '') {
  const cps = [...name].slice(0, 2).map((c) => c.codePointAt(0));
  if (cps.length === 2 && cps.every((c) => c >= 0x1F1E6 && c <= 0x1F1FF)) return String.fromCharCode(...cps.map((c) => c - 0x1F1E6 + 65));
  for (const [k, c] of FLAG_TABLE) if (name.toLowerCase().includes(k.toLowerCase())) return c;
  const m = name.match(/(?<![A-Za-z])(HK|TW|JP|SG|US|KR|UK|GB|DE|FR|CA|AU|RU|IN|TR|NL|TH|VN|MY|PH|MO)(?![a-z])/);
  return m ? (m[1] === 'UK' ? 'GB' : m[1]) : null;
}
const cleanName = (n = '') => n.replace(/^(?:[\u{1F1E6}-\u{1F1FF}]{2}\s*)+/u, '').trim() || n;
let PLATFORM = 'win32';
function Flag({ name }) {
  const c = flagCode(name);
  if (!c) return html`<span class="flag mute" style="font-size:18px">🌐</span>`;
  // Windows 不會顯示國旗 emoji，改用國家代碼
  if (PLATFORM === 'win32') return html`<span class="flag code">${c}</span>`;
  return html`<span class="flag">${String.fromCodePoint(...[...c].map((x) => 127397 + x.charCodeAt(0)))}</span>`;
}

// ---------- 小元件 ----------
const Switch = ({ on, onChange, disabled, label }) => html`<button class=${'switch' + (on ? ' on' : '')} disabled=${disabled} aria-label=${label} aria-pressed=${on} onClick=${() => onChange(!on)}></button>`;
const Check = ({ on, onChange }) => html`<button class=${'check' + (on ? ' on' : '')} aria-pressed=${on} onClick=${() => onChange(!on)}>${on && I('check')}</button>`;
const Seg = ({ options, value, onChange, tall, style }) => html`<div class=${'seg' + (tall ? ' tall' : '')} style=${style}>${options.map(([v, l]) => html`<button class=${value === v ? 'on' : ''} onClick=${() => onChange(v)}>${l}</button>`)}</div>`;
const Select = ({ options, value, onChange, style }) => html`<select class="field" style=${style} value=${value} onChange=${(e) => onChange(isNaN(+options[0][0]) ? e.target.value : +e.target.value)}>${options.map(([v, l]) => html`<option value=${v} selected=${v === value}>${l}</option>`)}</select>`;
const Search = ({ value, onInput, placeholder, style }) => html`<label class="search" style=${style}>${I('search')}<input placeholder=${placeholder} value=${value} onInput=${(e) => onInput(e.target.value)} aria-label=${placeholder} /></label>`;
const Pill = ({ on, text }) => html`<span class=${'pill' + (on ? '' : ' off')}><span class="dot" style=${{ background: on ? 'var(--accent)' : 'var(--mute)', width: '10px', height: '10px' }}></span>${text}</span>`;
const Tag = ({ text, kind = '', icon }) => html`<span class=${'tag ' + kind}>${icon && I(icon)}${text}</span>`;
const Stat = ({ icon, k, v, accent }) => html`<div class="card stat">${html`<span style=${{ color: accent ? 'var(--accent)' : 'var(--text)' }}>${I(icon)}</span>`}<div style="min-width:0"><div class="k">${k}</div><div class="v">${v}</div></div></div>`;
const Info = ({ k, v }) => html`<div class="info"><span>${k}</span><span title=${v}>${v}</span></div>`;
const Legend = () => html`<div class="legend"><span><i style="background:var(--accent)"></i>下載</span><span><i style="background:var(--mute)"></i>上傳</span></div>`;

function AppIcon({ path }) {
  const [src, setSrc] = useState(null);
  useEffect(() => { let alive = true; if (path) act('processIcon', path).then((s) => alive && setSrc(s)); else setSrc(null); return () => { alive = false; }; }, [path]);
  return src ? html`<img class="appicon" src=${src} alt="" />` : html`<span class="appicon ph">${I('app')}</span>`;
}
function appName(c) {
  const p = c.metadata.processPath || '';
  const m = p.match(/([^/\\]+)\.app[/\\]/);
  if (m) return m[1];
  if (c.metadata.process) return c.metadata.process.replace(/\.exe$/i, '');
  if (c.metadata.type === 'Inner') return 'mihomo 核心';
  return '未知';
}
// TUN 模式下 host 是空的，網域要從 sniffer 嗅探結果拿
const destination = (c) => c.metadata.host || c.metadata.sniffHost || c.metadata.destinationIP || '—';
const policyLabel = (c) => { const n = (c.chains || [])[0]; return n === 'DIRECT' ? '直連' : (n === 'REJECT' || n === 'REJECT-DROP') ? '拒絕' : '代理'; };

// ---------- 圖表 ----------
function niceMax(v, bytes) {
  const nice = (x) => { if (x <= 0) return 1; const e = Math.pow(10, Math.floor(Math.log10(x))); const f = x / e; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 4 ? 4 : f <= 5 ? 5 : f <= 8 ? 8 : 10) * e; };
  if (!bytes) return nice(v);
  const MB = 1048576;
  if (v >= MB) return nice(v / MB) * MB;
  if (v >= 1024) return nice(v / 1024) * 1024;
  return nice(v);
}
const speedLabel = (v) => v >= 1048576 ? `${Math.round(v / 1048576 * 100) / 100} MB/s` : v >= 1024 ? `${Math.round(v / 1024)} KB/s` : v === 0 ? '0 MB/s' : `${Math.round(v)} B/s`;

function Chart({ primary, secondary = [], labels = [], format, ticks = 4, minMax = 1, labelWidth = 70, bytes = false, height = 260 }) {
  const ref = useRef();
  useEffect(() => {
    const cv = ref.current; if (!cv) return;
    const dpr = window.devicePixelRatio || 1;
    const w = cv.clientWidth, h = cv.clientHeight;
    cv.width = w * dpr; cv.height = h * dpr;
    const g = cv.getContext('2d'); g.scale(dpr, dpr); g.clearRect(0, 0, w, h);
    const maxV = niceMax(Math.max(minMax, ...primary, ...secondary, 0), bytes);
    const bottom = labels.length ? 26 : 4;
    const pl = { x: labelWidth, y: 8, w: Math.max(10, w - labelWidth - 6), h: Math.max(10, h - 8 - bottom) };
    g.font = '12px "Segoe UI", sans-serif'; g.fillStyle = 'rgba(232,234,237,.8)'; g.strokeStyle = 'rgba(48,51,58,.8)'; g.lineWidth = 0.6;
    g.textBaseline = 'middle';
    for (let i = 0; i <= ticks; i++) {
      const y = pl.y + pl.h - pl.h * i / ticks;
      g.beginPath(); g.moveTo(pl.x, y); g.lineTo(pl.x + pl.w, y); g.stroke();
      g.textAlign = 'right'; g.fillText(format(maxV * i / ticks), labelWidth - 10, y);
    }
    labels.forEach((l, i) => {
      const x = pl.x + pl.w * i / Math.max(1, labels.length - 1);
      g.beginPath(); g.moveTo(x, pl.y); g.lineTo(x, pl.y + pl.h); g.stroke();
      g.textAlign = i === 0 ? 'left' : i === labels.length - 1 ? 'right' : 'center';
      g.fillText(l, x, pl.y + pl.h + 14);
    });
    g.strokeStyle = '#30333A'; g.lineWidth = 1; g.beginPath(); g.moveTo(pl.x, pl.y); g.lineTo(pl.x, pl.y + pl.h); g.stroke();
    const pts = (v) => v.length < 2 ? [] : v.map((val, i) => [pl.x + pl.w * i / (v.length - 1), pl.y + pl.h - pl.h * Math.min(val, maxV) / maxV]);
    const p1 = pts(primary);
    if (p1.length) {
      const grad = g.createLinearGradient(0, pl.y, 0, pl.y + pl.h);
      grad.addColorStop(0, 'rgba(61,219,180,.42)'); grad.addColorStop(1, 'rgba(61,219,180,.04)');
      g.beginPath(); p1.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y));
      g.lineTo(p1[p1.length - 1][0], pl.y + pl.h); g.lineTo(p1[0][0], pl.y + pl.h); g.closePath(); g.fillStyle = grad; g.fill();
      g.beginPath(); p1.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); g.strokeStyle = '#3DDBB4'; g.lineWidth = 1.8; g.lineJoin = 'round'; g.stroke();
    }
    const p2 = pts(secondary);
    if (p2.length) { g.beginPath(); p2.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); g.strokeStyle = 'rgba(255,255,255,.75)'; g.lineWidth = 1.2; g.stroke(); }
  });
  return html`<canvas class="chart" ref=${ref} style=${{ height: height + 'px' }}></canvas>`;
}
const timeLabels = (ts, n = 5, f = hms) => ts.length < 2 ? [] : Array.from({ length: n }, (_, i) => f(ts[Math.floor((ts.length - 1) * i / (n - 1))]));

function Modal({ title, children, onClose, width }) {
  return html`<div class="modal-bg" onClick=${(e) => e.target === e.currentTarget && onClose()}><div class="modal" style=${width ? { width: width + 'px' } : null} role="dialog" aria-label=${title}><h2>${title}</h2>${children}</div></div>`;
}

// ---------- 共用推導 ----------
const GROUP_TYPES = ['Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay'];
const isGroup = (s, n) => GROUP_TYPES.includes(s.proxies[n]?.type);
function groupList(s) {
  let list = (s.proxies.GLOBAL?.all || []).filter((n) => isGroup(s, n));
  if (!list.length && s.proxies[s.mainGroup]) list = [s.mainGroup];
  return [s.mainGroup, ...list.filter((g) => g !== s.mainGroup)].filter((g) => s.proxies[g]);
}
function members(s, g) {
  return (s.proxies[g]?.all || []).map((n) => { const h = s.proxies[n]?.history || []; return { name: n, type: s.proxies[n]?.type || '—', history: h, delay: h.length ? h[h.length - 1].delay : null }; });
}
function currentNode(s) {
  let n = s.proxies[s.mainGroup]?.now;
  for (let i = 0; i < 5 && n && s.proxies[n]?.now; i++) n = s.proxies[n].now;
  return n;
}
function nodeList(s) {
  const out = []; const seen = new Set();
  const order = s.store.subscriptions.map((x) => 'sub-' + String(x.id).toLowerCase()).concat([LOCAL]);
  for (const key of order) {
    const p = s.providers[key];
    if (!p || !['HTTP', 'File'].includes(p.vehicleType)) continue;
    for (const x of p.proxies || []) {
      if (seen.has(x.name)) continue; seen.add(x.name);
      const h = s.proxies[x.name]?.history || x.history || [];
      out.push({ name: x.name, type: x.type, provider: key, history: h, delay: h.length ? h[h.length - 1].delay : null });
    }
  }
  return out;
}
const providerDisplay = (s, key) => key === LOCAL ? '本機節點' : (s.store.subscriptions.find((x) => 'sub-' + String(x.id).toLowerCase() === key)?.name || key);

// ---------- 每秒變動的資料（速度、流量圖、連線）：只有需要的頁面訂閱，其他頁面不會每秒重畫 ----------
let liveData = { down: 0, up: 0, history: [], connections: [], activeCount: 0, connHistory: [] };
const liveSubs = new Set();
sky.onLive((x) => { liveData = x; liveSubs.forEach((f) => f(x)); });
function useLive() {
  const [l, setL] = useState(liveData);
  useEffect(() => { liveSubs.add(setL); return () => liveSubs.delete(setL); }, []);
  return l;
}

// 系統代理或 TUN 任一開著就算已連線
const isConn = (s) => s.systemProxyOn || s.tunActive;
const connLabel = (s) => !isConn(s) ? '未連線' : '已連線 · ' + [s.systemProxyOn && '系統代理', s.tunActive && 'TUN'].filter(Boolean).join('＋');

// ================= 頁面 =================

function Overview({ s, go }) {
  const L = useLive();
  const node = currentNode(s);
  const d = node ? s.proxies[node]?.history?.slice(-1)[0]?.delay : null;
  return html`<div class="page scroll">
    <div class="head"><h1 class="title">代理</h1><${Pill} on=${isConn(s)} text=${connLabel(s)} />
      <span class="spacer"></span>
      <button class="btn primary" disabled=${!s.coreReady} onClick=${() => act('toggleConnection')}>${isConn(s) ? '中斷連線' : '連線'}</button></div>
    <div class="stats">
      <${Stat} icon="swap" k="延遲" v=${fmtDelay(d)} />
      <${Stat} icon="down" k="下載" v=${fmtSpeed(L.down)} accent />
      <${Stat} icon="up" k="上傳" v=${fmtSpeed(L.up)} accent />
      <${Stat} icon="clock" k="連線時間" v=${s.connectedSince ? fmtDur(Date.now() - s.connectedSince) : '--:--:--'} />
    </div>
    <div class="row" style="align-items:stretch;gap:20px;flex-shrink:0">
      <div class="card grow" style="padding:20px">
        <div class="row"><h3 class="grow">即時流量</h3><${Legend} /></div>
        <div style="margin-top:10px"><${Chart} primary=${L.history.map((x) => x.down)} secondary=${L.history.map((x) => x.up)} labels=${timeLabels(L.history.map((x) => x.t), 6)} format=${speedLabel} ticks=${8} minMax=${1048576} bytes height=${190} /></div>
      </div>
      <div class="card" style="width:380px;flex-shrink:0;padding:20px;display:flex;flex-direction:column;gap:16px">
        <h3>當前節點</h3>
        <button class="btn" style="height:62px;justify-content:flex-start;font-size:19px;font-weight:400" onClick=${() => go('nodes')}>
          <${Flag} name=${node || ''} /><span class="grow" style="text-align:left;overflow:hidden;text-overflow:ellipsis">${cleanName(node || '未選擇')}</span>${I('chevR')}</button>
        <h3 style="margin-top:8px">路由模式</h3>
        <${Seg} tall options=${[['rule', '規則'], ['global', '全域'], ['direct', '直連']]} value=${s.store.settings.mode} onChange=${(m) => act('setMode', m)} />
      </div>
    </div>
    <div class="card" style="padding:20px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">
      <h3>最近連線</h3>
      <div class="thead"><span class="c f">應用程式</span><span class="c f">目的地</span><span class="c" style="width:200px">策略</span><span class="c" style="width:130px">流量</span></div>
      ${L.connections.length === 0 ? html`<div class="empty">${s.coreReady ? '目前沒有連線' : '核心尚未啟動'}</div>` :
        html`<div>${L.connections.slice(0, 8).map((c) => html`<div class="tr" key=${c.id}>
          <span class="c f row" style="gap:14px"><${AppIcon} path=${c.metadata.processPath} />${appName(c)}</span>
          <span class="c f">${destination(c)}</span>
          <span class="c" style="width:200px">${policyLabel(c) === '代理' ? '規則代理' : policyLabel(c)}</span>
          <span class="c num" style="width:130px">${fmtBytes(c.download + c.upload)}</span></div>`)}</div>`}
    </div>
  </div>`;
}

const TYPE_LABEL = { Selector: '手動選擇', URLTest: '自動測速', Fallback: '故障轉移', LoadBalance: '負載均衡', Relay: '鏈式代理' };
const delayColor = (d) => d === 0 ? 'var(--red)' : d < 200 ? 'var(--accent)' : d < 500 ? 'var(--amber)' : '#FB923C';
function resolveGroup(s, g) {
  let n = s.proxies[g]?.now;
  for (let i = 0; i < 8 && n && s.proxies[n]?.now; i++) n = s.proxies[n].now;
  return n;
}

// 節點頁（參考 Clash Verge）：所有策略組由上往下排列，點標題展開，節點以卡片格狀顯示，點卡片直接切換
function Nodes({ s, go }) {
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [sortDelay, setSortDelay] = useState(false);
  const [open, setOpen] = useState(() => new Set([s.mainGroup]));
  const [testing, setTesting] = useState(new Set());
  const [modal, setModal] = useState(null);
  const groups = groupList(s);
  const prof = s.store.subscriptions.find((x) => x.id === s.profileId);
  const toggle = (g) => { const n = new Set(open); n.has(g) ? n.delete(g) : n.add(g); setOpen(n); };
  const testGroup = async (g) => { setTesting((t) => new Set(t).add(g)); await act('testGroup', g); setTesting((t) => { const n = new Set(t); n.delete(g); return n; }); };
  const items = (g) => {
    let list = members(s, g).filter((n) => (filter !== 'fav' || s.store.favorites.includes(n.name) || isGroup(s, n.name))
      && (filter !== 'low' || isGroup(s, n.name) || (n.delay > 0 && n.delay < 150))
      && (!search || n.name.toLowerCase().includes(search.toLowerCase()) || n.type.toLowerCase().includes(search.toLowerCase())));
    if (sortDelay) list = [...list].sort((a, b) => (a.delay || 1e9) - (b.delay || 1e9));
    return list;
  };
  const allOpen = groups.length > 0 && groups.every((g) => open.has(g));

  return html`<div class="page">
    <div class="head"><div><div class="row" style="gap:18px"><h1 class="title">節點</h1><${Pill} on=${isConn(s)} text=${connLabel(s)} /></div>
      <div class="subtitle" style="margin-top:6px">${prof ? `使用訂閱「${prof.name}」的 ${groups.length} 個策略組` : '選擇連線節點'}</div></div>
      <span class="spacer"></span>
      <button class="btn" onClick=${() => setOpen(allOpen ? new Set() : new Set(groups))}>${allOpen ? '全部收合' : '全部展開'}</button>
      <button class="btn primary" onClick=${() => setModal({ text: '' })}>${I('plus')}新增節點</button></div>
    <div class="row">
      <${Search} value=${search} onInput=${setSearch} placeholder="搜尋節點" style="flex:0 1 340px" />
      ${[['all', '全部'], ['fav', '收藏'], ['low', '低延遲']].map(([v, l]) => html`<button class=${'chip' + (filter === v ? ' on' : '')} onClick=${() => setFilter(v)}>${l}</button>`)}
      <span class="grow"></span>
      <button class="btn sm" onClick=${() => setSortDelay(!sortDelay)}>${sortDelay ? '依延遲排序' : '原始順序'}</button>
    </div>
    ${groups.length === 0 ? html`<div class="empty">${I('cloud')}<div>${s.coreReady ? '還沒有節點，先到「訂閱」新增訂閱連結，或按「新增節點」貼上分享連結' : '核心尚未啟動'}</div>
        ${s.coreReady && html`<button class="btn sm" onClick=${() => go('subscriptions')}>前往訂閱</button>`}</div>` :
      html`<div style="flex:1;min-height:0;overflow-y:auto;display:flex;flex-direction:column;gap:12px;padding-bottom:8px">
        ${groups.map((g) => {
          const info = s.proxies[g]; const now = info?.now; const fin = resolveGroup(s, g); const isOpen = open.has(g);
          const selectable = info?.type === 'Selector';
          const fd = fin ? s.proxies[fin]?.history?.slice(-1)[0]?.delay : null;
          const list = isOpen ? items(g) : [];
          return html`<div class="card" style="padding:0;flex-shrink:0" key=${g}>
            <div class="row" style="height:66px;padding:0 16px;cursor:pointer;gap:12px" onClick=${() => toggle(g)}>
              <span style=${{ display: 'inline-flex', transform: isOpen ? 'rotate(90deg)' : 'none', transition: 'transform .15s', color: 'var(--mute)' }}>${I('chevR')}</span>
              <div style="min-width:0">
                <div class="row" style="gap:8px"><span style="font-size:17px;font-weight:600;white-space:nowrap">${g}</span>
                  <${Tag} text=${TYPE_LABEL[info?.type] || info?.type || ''} kind=${selectable ? '' : 'gray'} />
                  ${g === s.mainGroup && html`<span title="規則頁中策略選「代理」的規則走這個策略組"><${Tag} text="「代理」" kind="gray" /></span>`}</div>
                <div style="font-size:13px;color:rgba(232,234,237,.7);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
                  ${now ? cleanName(now) : ''}${fin && fin !== now ? ` → ${cleanName(fin)}` : ''}</div>
              </div>
              <span class="grow"></span>
              ${fd != null && html`<span class="num" style=${{ color: delayColor(fd), fontWeight: 600, fontSize: '14px' }}>${fmtDelay(fd)}</span>`}
              <span class="mute" style="font-size:13px;background:var(--field);border-radius:999px;padding:3px 8px">${info?.all?.length || 0}</span>
              <button class="icon-btn" title="測試這組的延遲" aria-label="測試這組的延遲" disabled=${testing.has(g)} onClick=${(e) => { e.stopPropagation(); testGroup(g); }}>${testing.has(g) ? '…' : I('gauge')}</button>
            </div>
            ${isOpen && html`<div class="hr"></div>
              ${list.length === 0 ? html`<div class="mute" style="padding:20px;text-align:center;font-size:14px">沒有符合的節點</div>` :
                html`<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(215px,1fr));gap:10px;padding:14px">
                  ${list.map((n) => { const sub = isGroup(s, n.name); const sel = n.name === now; const fav = s.store.favorites.includes(n.name);
                    return html`<div key=${n.name} title=${sub ? `子策略組「${n.name}」` : n.name}
                      style=${{ padding: '10px 12px', borderRadius: '9px', cursor: selectable || sub ? 'pointer' : 'default', background: sel ? 'var(--row-sel)' : 'rgba(36,38,43,.6)', border: `${sel ? 1.5 : 1}px solid ${sel ? 'var(--accent)' : 'var(--line)'}` }}
                      onClick=${() => { if (selectable && !sel) act('select', n.name, g); else if (sub && !open.has(n.name)) toggle(n.name); }}
                      onContextMenu=${(e) => { e.preventDefault(); act('toggleFavorite', n.name); }}>
                      <div class="row" style="gap:6px">${sub ? html`<span style="color:var(--accent);display:inline-flex">${I('layers')}</span>` : html`<${Flag} name=${n.name} />`}
                        <span style="font-size:14px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1">${cleanName(n.name)}</span>
                        ${fav && html`<span style="color:var(--accent);font-size:11px">★</span>`}</div>
                      <div class="row" style="gap:6px;margin-top:8px;font-size:12px">
                        <span class="mute" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1">${sub ? `${TYPE_LABEL[n.type] || n.type} → ${cleanName(resolveGroup(s, n.name) || '—')}` : n.type}</span>
                        ${!sub && html`<span class="num" style=${{ fontWeight: 600, color: n.delay != null ? delayColor(n.delay) : 'var(--mute)', cursor: 'pointer' }} title="測試這個節點"
                          onClick=${(e) => { e.stopPropagation(); act('testOne', n.name); }}>${n.delay == null ? '測速' : fmtDelay(n.delay)}</span>`}</div>
                    </div>`; })}
                </div>`}`}
          </div>`; })}
      </div>`}
    ${modal && html`<${Modal} title="新增節點" onClose=${() => setModal(null)}>
      <div class="mute" style="font-size:14px">貼上節點分享連結，一行一個。支援 ss://、vmess://、vless://、trojan://、hysteria2://、tuic:// 等。新增的節點會放在「其他節點」策略組（設定檔模式）或「代理」策略組。</div>
      <textarea class="field" rows="9" value=${modal.text} onInput=${(e) => setModal({ text: e.target.value })}></textarea>
      <div class="row"><span class="grow"></span><button class="btn sm" onClick=${() => setModal(null)}>取消</button>
        <button class="btn primary" disabled=${!modal.text.includes('://')} onClick=${() => { act('addLinks', modal.text); setModal(null); }}>新增</button></div><//>`}
  </div>`;
}

function Subscriptions({ s }) {
  const subs = s.store.subscriptions;
  const [selId, setSelId] = useState(subs[0]?.id || null);
  const [draft, setDraft] = useState(subs[0] ? { ...subs[0] } : null);
  const [showURL, setShowURL] = useState(false);
  const pick = (sub) => { setSelId(sub.id); setDraft({ ...sub }); setShowURL(false); };
  const pname = (sub) => 'sub-' + String(sub.id).toLowerCase();
  const live = subs.find((x) => x.id === draft?.id);
  const updating = (id) => s.updatingSubs.includes(id);
  const [profGroups, setProfGroups] = useState([]);
  useEffect(() => { if (draft?.id) act('profileInfo', draft.id).then((x) => setProfGroups(x.groups)); }, [draft?.id, live?.updatedAt]);

  return html`<div class="page">
    <div class="head"><h1 class="title">訂閱</h1><span class="subtitle">管理節點來源與更新</span><span class="spacer"></span>
      <button class="btn" disabled=${!subs.length || !s.coreReady} onClick=${() => act('updateAll')}>${I('refresh')}全部更新</button>
      <button class="btn primary" onClick=${async () => { const id = await act('newSubscription'); const snap = await sky.snapshot(); const n = snap.store.subscriptions.find((x) => x.id === id); if (n) pick(n); }}>${I('plus')}新增訂閱</button></div>
    <div class="split">
      <div class="grow" style="overflow-y:auto;display:flex;flex-direction:column;gap:20px;padding:2px">
        ${!subs.length && html`<div class="card empty" style="min-height:260px">${I('link')}<div style="font-size:18px;font-weight:600;color:var(--text)">還沒有訂閱</div><div>按右上角「新增訂閱」，貼上機場給你的訂閱連結</div></div>`}
        ${subs.map((sub) => { const count = s.subCounts?.[sub.id];
          const used = (sub.download || 0) + (sub.upload || 0); const total = sub.total || 0;
          return html`<div class=${'card' + (sub.id === selId ? ' hl' : '')} style="padding:22px 26px;display:flex;flex-direction:column;gap:16px;cursor:pointer" key=${sub.id} onClick=${() => pick(sub)}>
            <div class="row" onClick=${(e) => e.target.closest('button') && e.stopPropagation()}>
              <${Check} on=${sub.enabled} onChange=${(v) => act('setSubEnabled', sub.id, v)} />
              <span style="font-size:22px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${sub.name}</span>
              <${Tag} text=${sub.enabled ? '已啟用' : '已停用'} kind=${sub.enabled ? '' : 'gray'} />
              ${sub.isProfile && sub.useProfile !== false && html`<${Tag} text="設定檔" kind=${s.profileId === sub.id ? '' : 'gray'} />`}<span class="grow"></span>
              <${Switch} on=${sub.enabled} label=${'啟用 ' + sub.name} onChange=${(v) => act('setSubEnabled', sub.id, v)} />
              <button class="icon-btn" aria-label="刪除訂閱" title="刪除訂閱" onClick=${() => { if (confirm(`確定要刪除「${sub.name}」？`)) act('deleteSubscription', sub.id); }}>${I('x')}</button>
              <button class="btn sm" disabled=${updating(sub.id) || !sub.url || !sub.enabled || !s.coreReady} onClick=${() => act('updateSubscription', sub.id)}>${updating(sub.id) ? '更新中' : '更新'}</button>
            </div>
            <div class="row" style="font-size:17px;color:rgba(232,234,237,.9)">${I('server')}<span>節點數：${count ?? '—'}</span><span class="sep" style="height:20px"></span>${I('refresh')}<span>最後更新：${ago(sub.updatedAt)}</span></div>
            ${sub.enabled && html`<div class="hr"></div>${total > 0 ? html`
              <div class="row" style="font-size:17px"><span class="grow">方案流量（來源提供）</span><span class="num">已用 ${fmtBytes(used)} / ${fmtBytes(total)}</span></div>
              <div class="bar"><div style=${{ width: Math.min(100, used / total * 100) + '%' }}></div></div>
              ${sub.expire > 0 && html`<div class="mute" style="font-size:14px">到期：${new Date(sub.expire * 1000).toLocaleDateString('zh-TW')}</div>`}`
              : html`<div class="row" style="font-size:17px">${I('info')}流量資訊未提供</div>`}`}
          </div>`; })}
      </div>
      <div class="card" style="width:460px;flex-shrink:0;padding:24px;display:flex;flex-direction:column;gap:12px">
        ${draft ? html`
          <div style="flex:1;overflow-y:auto;display:flex;flex-direction:column;gap:12px">
            <div style="font-size:26px;font-weight:700">${draft.name || '未命名'}</div>
            <label class="lbl">訂閱名稱</label><input class="field" value=${draft.name} onInput=${(e) => setDraft({ ...draft, name: e.target.value })} />
            <label class="lbl">訂閱連結</label>
            <div class="search" style="height:46px"><input type=${showURL ? 'text' : 'password'} placeholder="https://" value=${draft.url} onInput=${(e) => setDraft({ ...draft, url: e.target.value })} />
              <button class="icon-btn" style="width:30px" aria-label=${showURL ? '隱藏連結' : '顯示連結'} onClick=${() => setShowURL(!showURL)}>${I(showURL ? 'eyeOff' : 'eye')}</button></div>
            <div class="hr" style="margin:6px 0"></div>
            <div class="row"><span class="grow" style="font-size:17px">自動更新</span><${Switch} on=${draft.autoUpdate} label="自動更新" onChange=${(v) => setDraft({ ...draft, autoUpdate: v })} /></div>
            ${draft.autoUpdate && html`<div class="row"><span class="grow" style="font-size:17px;padding-left:18px">更新間隔</span>
              <${Select} style="width:200px" options=${[[1, '每 1 小時'], [3, '每 3 小時'], [6, '每 6 小時'], [12, '每 12 小時'], [24, '每 24 小時']]} value=${draft.intervalHours} onChange=${(v) => setDraft({ ...draft, intervalHours: v })} /></div>`}
            ${live?.isProfile && html`<div class="hr" style="margin:6px 0"></div>
              <div class="row"><span style="font-size:17px">使用訂閱的分組與規則</span><span class="mute" title="這份訂閱是完整的 mihomo 設定檔。開啟時沿用它的策略組、規則和規則集；關閉時只取節點。同時只會有一份訂閱當設定檔。" style="display:inline-flex;width:18px">${I('info')}</span><span class="grow"></span>
                <${Switch} on=${draft.useProfile !== false} label="使用訂閱的分組與規則" onChange=${(v) => setDraft({ ...draft, useProfile: v })} /></div>
              ${draft.useProfile !== false && profGroups.length > 0 && html`<div class="row"><span class="grow" style="font-size:17px;padding-left:18px" title="規則頁中策略選「代理」的規則會走這個策略組">「代理」對應</span>
                <${Select} style="width:220px" options=${profGroups.map((g) => [g, g])} value=${profGroups.includes(draft.mainGroup) ? draft.mainGroup : profGroups[0]} onChange=${(v) => setDraft({ ...draft, mainGroup: v })} /></div>`}`}
            <div class="hr" style="margin:6px 0"></div>
            <div class="row"><span style="font-size:17px">透過目前代理更新</span><span class="mute" title="用目前選擇的節點下載訂閱；第一次下載時還沒有節點，會先直接連線" style="display:inline-flex;width:18px">${I('info')}</span><span class="grow"></span>
              <${Switch} on=${draft.viaProxy} label="透過目前代理更新" onChange=${(v) => setDraft({ ...draft, viaProxy: v })} /></div>
            <div class="hr" style="margin:6px 0"></div>
            <label class="lbl">更新狀態</label>
            ${updating(draft.id) ? html`<div>更新中…</div>` : live?.statusOK != null ? html`<div><span class="status-ok" style=${{ background: live.statusOK ? 'var(--pill)' : 'var(--red-dim)', color: live.statusOK ? 'var(--accent)' : 'var(--red-text)' }}>${I(live.statusOK ? 'check' : 'x')}${live.statusMessage}</span></div>` : html`<div class="mute">尚未更新</div>`}
          </div>
          <button class="btn primary full" disabled=${!String(draft.url || '').trim()} onClick=${() => act('saveSubscription', draft)}>儲存變更</button>`
        : html`<div class="empty">選擇或新增一個訂閱</div>`}
      </div>
    </div>
    <div class="hr"></div>
    <div class="row" style="font-size:15px;color:rgba(232,234,237,.85);gap:10px;flex-shrink:0"><span style="display:inline-flex;width:18px">${I('info')}</span>${showURL ? '訂閱連結目前顯示中' : '訂閱連結已隱藏'}</div>
  </div>`;
}

// ---------- 規則比對（給「測試規則」用） ----------
function ipv4(s) { const p = s.split('.'); if (p.length !== 4 || p.some((x) => !/^\d+$/.test(x) || +x > 255)) return null; return p.reduce((a, b) => (a << 8 | +b) >>> 0, 0); }
function cidr(ip, block) { const [b, bits = '32'] = block.split('/'); const a = ipv4(ip), n = ipv4(b); if (a == null || n == null) return false; const k = +bits; if (k === 0) return true; const m = k >= 32 ? 0xFFFFFFFF : (~(0xFFFFFFFF >>> k)) >>> 0; return ((a & m) >>> 0) === ((n & m) >>> 0); }
function matchRule(input, rules, def) {
  let host; try { host = new URL(input.includes('://') ? input : 'https://' + input).hostname.toLowerCase(); } catch { host = input.toLowerCase(); }
  for (let i = 0; i < rules.length; i++) {
    const r = rules[i]; if (!r.enabled) continue;
    const p = String(r.payload).toLowerCase().trim();
    const hit = r.type === 'DOMAIN' ? host === p : r.type === 'DOMAIN-SUFFIX' ? (host === p || host.endsWith('.' + p)) : r.type === 'DOMAIN-KEYWORD' ? host.includes(p)
      : r.type === 'DOMAIN-REGEX' ? (() => { try { return new RegExp(r.payload).test(host); } catch { return false; } })() : r.type === 'IP-CIDR' ? cidr(host, p) : false;
    if (hit) return { index: i, policy: r.policy };
  }
  return { index: null, policy: def };
}

function Rules({ s }) {
  const rules = s.store.rules;
  const [search, setSearch] = useState('');
  const [draft, setDraft] = useState(null);
  const [test, setTest] = useState('https://example.com');
  const [result, setResult] = useState(null);
  const [importing, setImporting] = useState(null);
  const [dragIdx, setDragIdx] = useState(null);
  const [overIdx, setOverIdx] = useState(null);
  const isNew = draft && !rules.some((r) => r.id === draft.id);
  const prof = s.store.subscriptions.find((x) => x.id === s.profileId);
  const [subRules, setSubRules] = useState([]);
  useEffect(() => { if (prof) act('profileInfo', prof.id).then((x) => setSubRules(x.rules)); else setSubRules([]); }, [prof?.id, prof?.updatedAt]);
  const ph = { 'DOMAIN-SUFFIX': 'example.com', DOMAIN: 'www.example.com', 'DOMAIN-KEYWORD': 'google', 'IP-CIDR': '192.168.0.0/16', 'SRC-IP-CIDR': '192.168.0.0/16', 'IP-CIDR6': '2001:db8::/32', 'DST-PORT': '443', 'PROCESS-NAME': 'Telegram.exe', GEOIP: 'CN', GEOSITE: 'google' };
  const pkind = (p) => p === '拒絕' ? 'red' : p === '直連' ? 'gray' : '';
  const save = () => { const d = { ...draft, payload: draft.payload.trim() }; act('setRules', isNew ? [d, ...rules] : rules.map((r) => r.id === d.id ? d : r)); setDraft(d); };
  const toggle = (r, v) => act('setRules', rules.map((x) => x.id === r.id ? { ...x, enabled: v } : x));
  const drop = (to) => { if (dragIdx == null || dragIdx === to) return; const a = [...rules]; const [m] = a.splice(dragIdx, 1); a.splice(to > dragIdx ? to - 1 : to, 0, m); act('setRules', a); };
  const doImport = (text) => {
    const added = [];
    for (let line of text.split(/\r?\n/)) {
      line = line.trim().replace(/^-\s*/, '').replace(/^["']|["']$/g, '');
      const parts = line.split(',').map((x) => x.trim());
      if (parts.length < 2 || !RULE_TYPES.includes(parts[0].toUpperCase())) continue;
      const pol = (parts[2] || '').toUpperCase();
      added.push({ id: crypto.randomUUID(), type: parts[0].toUpperCase(), payload: parts[1], enabled: true,
        policy: ['DIRECT', '直連'].includes(pol) ? '直連' : ['REJECT', 'REJECT-DROP', '拒絕'].includes(pol) ? '拒絕' : pol === '自動選擇' ? '自動選擇' : '代理' });
    }
    if (added.length) act('setRules', [...rules, ...added]);
  };

  return html`<div class="page">
    <div class="head"><h1 class="title">規則</h1><span class="subtitle div">依順序比對，優先套用第一條符合的規則</span><span class="spacer"></span>
      <button class="btn" onClick=${() => setImporting('')}>${I('import')}匯入</button>
      <button class="btn primary" onClick=${() => setDraft({ id: crypto.randomUUID(), type: 'DOMAIN-SUFFIX', payload: '', policy: '代理', enabled: true })}>${I('plus')}新增規則</button></div>
    <div class="card row" style="padding:14px;gap:18px;flex-shrink:0">
      <${Seg} options=${[['rule', '規則'], ['global', '全域'], ['direct', '直連']]} value=${s.store.settings.mode} onChange=${(m) => act('setMode', m)} style="flex:0 1 340px;min-width:220px" />
      <span class="sep"></span>
      ${prof ? html`<span class="mute" style="font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">使用訂閱「${prof.name}」的規則，你的規則優先</span>` : html`<span style="font-size:17px;white-space:nowrap">預設策略：</span>
      <${Select} options=${POLICIES.map((p) => [p, p])} value=${s.store.settings.defaultPolicy} onChange=${(p) => act('setDefaultPolicy', p)} style="flex:0 1 200px;min-width:120px" />`}
      <span class="grow"></span>
      <${Search} value=${search} onInput=${setSearch} placeholder="搜尋規則" style="flex:0 1 340px" />
    </div>
    <div class="split">
      <div class="card table" style="padding:0">
        <div class="thead plain" style="padding:0 10px"><span style="width:40px"></span><span class="c" style="width:50px">#</span><span class="c" style="width:80px">啟用</span><span class="c" style="width:170px">類型</span><span class="c f">比對內容</span><span class="c" style="width:120px">策略</span></div>
        <div class="hr"></div>
        <div class="tbody">
          ${rules.map((r, i) => (!search || r.payload.toLowerCase().includes(search.toLowerCase()) || r.type.toLowerCase().includes(search.toLowerCase())) && html`
            <div key=${r.id} class=${'tr click' + (draft?.id === r.id ? ' sel' : '') + (overIdx === i ? ' dragover' : '')} style="min-height:62px;padding:0 10px;border-radius:0"
              draggable="true" onDragStart=${() => setDragIdx(i)} onDragEnd=${() => { setDragIdx(null); setOverIdx(null); }}
              onDragOver=${(e) => { e.preventDefault(); setOverIdx(i); }} onDrop=${(e) => { e.preventDefault(); drop(i); setOverIdx(null); }}
              onClick=${() => setDraft({ ...r })}>
              <span class="drag-handle">${I('grip')}</span><span class="c num" style="width:50px">${i + 1}</span>
              <span class="c" style="width:80px" onClick=${(e) => e.stopPropagation()}><${Switch} on=${r.enabled} label=${'啟用規則 ' + (i + 1)} onChange=${(v) => toggle(r, v)} /></span>
              <span class="c" style="width:170px">${r.type}</span><span class="c f">${r.payload}</span>
              <span class="c" style="width:120px"><${Tag} text=${r.policy} kind=${pkind(r.policy)} icon=${POLICY_ICON[r.policy]} /></span></div>`)}
          ${prof ? html`<div class="tr" style="min-height:44px;background:var(--header);font-size:14px;font-weight:500">以下是訂閱「${prof.name}」的 ${subRules.length} 條規則（唯讀，隨訂閱更新）</div>
            ${subRules.map((raw, i) => (!search || raw.toLowerCase().includes(search.toLowerCase())) && (() => {
              const parts = raw.split(','); const compound = /^(AND|OR|NOT|SUB-RULE)/.test(raw);
              const type = parts[0]; const target = compound ? parts[parts.length - 1] : (parts.length > 2 ? parts[2] : parts[1] || '');
              const payload = compound ? raw : (parts.length > 2 ? parts[1] : (type === 'MATCH' ? '其他連線' : ''));
              return html`<div class="tr" style="min-height:54px;padding:0 10px;color:rgba(232,234,237,.75)" key=${'s' + i} title=${raw}>
                <span style="width:40px"></span><span class="c num" style="width:50px">${rules.length + i + 1}</span><span style="width:80px"></span>
                <span class="c" style="width:170px">${type}</span><span class="c f">${payload}</span>
                <span class="c" style="width:120px"><${Tag} text=${target} kind=${target === 'REJECT' ? 'red' : /DIRECT|直连|直連/.test(target) ? 'gray' : ''} /></span></div>`; })())}` : html`
          <div class="tr" style="min-height:62px;padding:0 10px;border-bottom:0" title="最後一條：沒被上面規則命中的連線都走「預設策略」"
            onDragOver=${(e) => { e.preventDefault(); setOverIdx(rules.length); }} onDrop=${(e) => { e.preventDefault(); drop(rules.length); setOverIdx(null); }}>
            <span class="drag-handle">${I('lock')}</span><span class="c num" style="width:50px">${rules.length + 1}</span><span style="width:80px"></span>
            <span class="c" style="width:170px">MATCH</span><span class="c f">其他連線</span>
            <span class="c" style="width:120px"><${Tag} text=${s.store.settings.defaultPolicy} kind=${pkind(s.store.settings.defaultPolicy)} icon=${POLICY_ICON[s.store.settings.defaultPolicy]} /></span></div>`}
        </div>
      </div>
      <div class="card" style="width:320px;flex-shrink:0;padding:22px;display:flex;flex-direction:column;gap:10px">
        <div style="font-size:24px;font-weight:700">${isNew ? '新增規則' : '編輯規則'}</div>
        ${draft ? html`
          <label class="lbl" style="margin-top:6px">類型</label><${Select} options=${RULE_TYPES.map((t) => [t, t])} value=${draft.type} onChange=${(v) => setDraft({ ...draft, type: v })} />
          <label class="lbl" style="margin-top:6px">比對內容</label><input class="field" placeholder=${ph[draft.type] || ''} value=${draft.payload} onInput=${(e) => setDraft({ ...draft, payload: e.target.value })} />
          <label class="lbl" style="margin-top:6px">策略</label><${Select} options=${POLICIES.map((p) => [p, p])} value=${draft.policy} onChange=${(v) => setDraft({ ...draft, policy: v })} />
          <div class="row" style="margin-top:10px"><span class="grow" style="font-size:17px">啟用</span><${Switch} on=${draft.enabled} label="啟用" onChange=${(v) => setDraft({ ...draft, enabled: v })} /></div>
          <span class="grow"></span>
          <button class="btn primary full" disabled=${!draft.payload.trim()} onClick=${save}>儲存變更</button>
          ${!isNew && html`<button class="btn danger full" onClick=${() => { act('setRules', rules.filter((r) => r.id !== draft.id)); setDraft(null); }}>刪除規則</button>`}`
        : html`<div class="empty">點選左邊的規則來編輯，或按「新增規則」</div>`}
      </div>
    </div>
    <div class="card row" style="padding:18px;gap:18px;flex-shrink:0">
      <span style="font-size:20px;font-weight:600;white-space:nowrap">測試規則</span>
      <input class="field grow" value=${test} onInput=${(e) => setTest(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && setResult(matchRule(test, rules, s.store.settings.defaultPolicy))} aria-label="網址或網域" />
      <button class="btn primary" style="width:100px" onClick=${() => setResult(matchRule(test, rules, s.store.settings.defaultPolicy))}>測試</button>
      <span class="sep"></span>
      <div class="row" style="flex:0 1 360px;min-width:200px;height:46px;padding:0 18px;border-radius:9px;background:rgba(26,58,50,.7);color:var(--accent);font-size:17px;font-weight:500;white-space:nowrap;overflow:hidden">
        ${result ? html`<span style="display:inline-flex;width:20px">${I('check')}</span>${result.index != null ? `命中第 ${result.index + 1} 條 · ${result.policy}` : `未命中 · 使用預設策略 ${result.policy}`}` : html`<span class="mute">輸入網址後按「測試」</span>`}</div>
    </div>
    ${importing != null && html`<${Modal} title="匯入規則" onClose=${() => setImporting(null)} width=${620}>
      <div class="mute" style="font-size:14px">一行一條，格式：類型,內容,策略（例如 DOMAIN-SUFFIX,google.com,代理）。策略可寫 代理 / 直連 / 拒絕 或 DIRECT / REJECT；可直接貼 Clash 設定檔裡 rules: 底下的內容。</div>
      <textarea class="field" rows="11" value=${importing} onInput=${(e) => setImporting(e.target.value)}></textarea>
      <div class="row"><span class="grow"></span><button class="btn sm" onClick=${() => setImporting(null)}>取消</button><button class="btn primary" onClick=${() => { doImport(importing); setImporting(null); }}>匯入</button></div><//>`}
  </div>`;
}

function Connections({ s }) {
  const L = useLive();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [sel, setSel] = useState(null);
  const list = L.connections.filter((c) => (filter === 'all' || (filter === 'proxy' && policyLabel(c) === '代理') || (filter === 'direct' && policyLabel(c) === '直連'))
    && (!search || appName(c).toLowerCase().includes(search.toLowerCase()) || destination(c).toLowerCase().includes(search.toLowerCase())));
  const d = L.connections.find((c) => c.id === sel) || list[0];
  useEffect(() => { act('watchConnection', d?.id || null); }, [d?.id]);
  useEffect(() => () => act('watchConnection', null), []);
  const kind = (c) => ({ '直連': 'gray', '拒絕': 'red' })[policyLabel(c)] || 'solid';
  const h = L.connHistory;

  return html`<div class="page">
    <div class="head"><h1 class="title">連線</h1><${Pill} on=${!s.pausedConnections} text=${s.pausedConnections ? '已暫停' : '即時更新'} /><span class="spacer"></span>
      <button class="btn" onClick=${() => act('setPaused', !s.pausedConnections)}>${I(s.pausedConnections ? 'play' : 'pause')}${s.pausedConnections ? '繼續更新' : '暫停更新'}</button>
      <button class="btn danger" disabled=${!L.connections.length} onClick=${() => act('closeAll')}>中斷全部</button></div>
    <div class="stats three">
      <${Stat} icon="link" k="活動連線" v=${L.activeCount} />
      <${Stat} icon="down" k="下載" v=${fmtSpeed(L.down)} accent />
      <${Stat} icon="up" k="上傳" v=${fmtSpeed(L.up)} accent />
    </div>
    <div class="split">
      <div class="card table" style="padding:16px;gap:14px">
        <div class="row" style="gap:18px"><${Search} value=${search} onInput=${setSearch} placeholder="搜尋應用程式或目的地" style="flex:1" /><span class="sep"></span>
          <${Seg} options=${[['all', '全部'], ['proxy', '代理'], ['direct', '直連']]} value=${filter} onChange=${setFilter} style="flex:0 1 280px;min-width:200px" /></div>
        <div class="thead"><span class="c f">應用程式</span><span class="c f">目的地</span><span class="c" style="width:90px">策略</span><span class="c" style="width:100px">下載</span><span class="c" style="width:90px">上傳</span></div>
        ${list.length === 0 ? html`<div class="empty">${s.coreReady ? '目前沒有連線' : '核心尚未啟動'}</div>` :
          html`<div class="tbody">${list.map((c) => html`<div key=${c.id} class=${'tr click' + (c.id === d?.id ? ' sel' : '')} onClick=${() => setSel(c.id)}>
            <span class="c f row" style="gap:14px"><${AppIcon} path=${c.metadata.processPath} />${appName(c)}</span>
            <span class="c f">${destination(c)}</span><span class="c" style="width:90px"><${Tag} text=${policyLabel(c)} kind=${kind(c)} /></span>
            <span class="c num" style="width:100px">${fmtBytes(c.download)}</span><span class="c num" style="width:90px">${fmtBytes(c.upload)}</span></div>`)}</div>`}
        <div class="hr"></div>
        <div style="font-size:15px;color:rgba(232,234,237,.85)">顯示 ${list.length} 筆 · 共 ${L.activeCount} 條活動連線</div>
      </div>
      <div class="card detail" style="width:420px;padding:20px">
        <h3>連線詳情</h3>
        ${d ? html`
          <div class="row" style="gap:16px"><span style="transform:scale(1.8);transform-origin:left center;width:56px;display:inline-flex"><${AppIcon} path=${d.metadata.processPath} /></span>
            <div style="min-width:0"><div style="font-size:21px;font-weight:600">${appName(d)}</div><div class="mute" style="font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title=${d.metadata.processPath}>${d.metadata.processPath || '—'}</div></div></div>
          <div class="hr"></div>
          <div>
            <${Info} k="目的地" v=${`${destination(d)}:${d.metadata.destinationPort || ''}`} />
            ${d.metadata.destinationIP && d.metadata.destinationIP !== destination(d) && html`<${Info} k="IP 位址" v=${d.metadata.destinationIP} />`}
            <${Info} k="協定" v=${(d.metadata.network || '').toUpperCase()} />
            <div class="info"><span>節點</span><span class="row" style="gap:6px">${policyLabel(d) === '代理' && html`<${Flag} name=${(d.chains || [])[0] || ''} />`}${cleanName((d.chains || [])[0] || '—')}</span></div>
            <${Info} k="命中規則" v=${d.rule ? (d.rulePayload ? `${d.rule} · ${d.rulePayload}` : d.rule) : '—'} />
            <${Info} k="持續時間" v=${d.start ? fmtDur(Date.now() - Date.parse(d.start)) : '—'} />
          </div>
          <div class="hr"></div>
          <div class="row"><span class="grow" style="font-size:17px;font-weight:600">傳輸速率</span><${Legend} /></div>
          <${Chart} primary=${h.map((x) => x.down)} secondary=${h.map((x) => x.up)} labels=${timeLabels(h.map((x) => x.t), 5, hm)} format=${speedLabel} minMax=${65536} labelWidth=${72} bytes height=${130} />
          <span class="grow"></span>
          <button class="btn danger full" onClick=${() => { act('closeConnection', d.id); setSel(null); }}>${I('x')}中斷此連線</button>`
        : html`<div class="empty">選擇一條連線查看詳情</div>`}
      </div>
    </div>
  </div>`;
}

const Section = ({ title, children }) => html`<div class="card" style="padding:22px;display:flex;flex-direction:column;gap:14px"><h3 style="font-size:20px">${title}</h3>${children}</div>`;
const ToggleRow = ({ title, hint, on, onChange, disabled }) => html`<div class="row"><div class="grow"><div style="font-size:17px">${title}</div>${hint && html`<div class="mute" style="font-size:13px;margin-top:4px">${hint}</div>`}</div><${Switch} on=${on} onChange=${onChange} disabled=${disabled} label=${title} /></div>`;

function Settings({ s }) {
  const st = s.store.settings;
  const [mp, setMp] = useState(String(st.mixedPort));
  const [cpt, setCp] = useState(String(st.controllerPort));
  const [url, setUrl] = useState(st.testURL);
  const [login, setLogin] = useState(false);
  const [log, setLog] = useState(null);
  const [term, setTerm] = useState('');
  const [ssidName, setSsidName] = useState('');
  const [ssidAction, setSsidAction] = useState('direct');
  useEffect(() => { act('launchAtLogin').then(setLogin); act('terminalCommand').then(setTerm); }, [st.mixedPort]);
  const applyNet = () => {
    const a = +mp, b = +cpt;
    if (!(a >= 1 && a <= 65535 && b >= 1 && b <= 65535 && a !== b)) return alert('連接埠要是 1–65535 之間、不重複的數字');
    act('setSettings', { mixedPort: a, controllerPort: b, testURL: url.trim() || 'https://www.gstatic.com/generate_204' });
  };
  const isWin = s.platform === 'win32';

  return html`<div class="page scroll">
    <div class="head"><h1 class="title">設定</h1><span class="subtitle">連接埠、TUN、核心與更新</span></div>
    <div class="row" style="align-items:flex-start;gap:20px">
      <div class="grow" style="display:flex;flex-direction:column;gap:20px">
        <${Section} title="一般">
          <${ToggleRow} title="開機時自動啟動 Sky" on=${login} onChange=${(v) => { act('setLaunchAtLogin', v); setLogin(v); }} />
          <div class="hr"></div>
          <${ToggleRow} title="啟動後自動連線" hint="打開 App 時自動設定系統代理" on=${st.autoConnect} onChange=${(v) => act('setSettings', { autoConnect: v })} />
          <div class="hr"></div>
          <div class="row"><div class="grow"><div style="font-size:17px">終端代理命令</div><div class="mute" style="font-size:12px;font-family:Consolas,Menlo,monospace;margin-top:4px;user-select:text;word-break:break-all">${term}</div></div>
            <button class="btn sm" onClick=${() => act('copyTerminal')}>複製</button></div>
        <//>
        <${Section} title="增強模式（TUN）">
          <${ToggleRow} title="TUN 模式" hint=${isWin ? '接管所有程式的流量（包括不理會系統代理的遊戲、終端程式）。需要以系統管理員身分執行 Sky。' : '接管所有程式的流量'}
            on=${!!st.tun} onChange=${(v) => act('setTun', v)} disabled=${!s.coreReady || s.busy} />
          <div class="row" style="font-size:14px"><span class="mute grow">目前狀態</span>
            ${s.tunActive ? html`<${Tag} text="已啟用" icon="shield" />` : st.tun && isWin && !s.isAdmin ? html`<${Tag} text="需要系統管理員權限" kind="red" />` : html`<${Tag} text="未啟用" kind="gray" />`}</div>
          ${isWin && html`<div class="mute" style="font-size:13px">目前${s.isAdmin ? '已' : '未'}以系統管理員身分執行。TUN 開啟時建議同時保留系統代理，兩者可以並存。</div>`}
        <//>
        <${Section} title="Wi-Fi 自動切換（SSID）">
          <${ToggleRow} title="依 Wi-Fi 自動切換" hint="連到指定的 Wi-Fi 時自動切換模式或中斷代理，離開後恢復原本的設定" on=${!!st.ssidEnabled} onChange=${(v) => act('enableSSID', v)} />
          ${st.ssidEnabled && html`<div class="hr"></div>
            <div class="row" style="font-size:15px"><span class="mute grow">目前 Wi-Fi</span><span style="font-weight:500">${s.currentSSID || (s.platform === 'win32' ? '未連線 Wi-Fi（或系統未允許讀取位置）' : '只有 Windows 版會偵測')}</span></div>
            ${(st.ssidRules || []).map((r) => html`<div class="row" key=${r.id}><span style=${{ color: r.ssid === s.currentSSID ? 'var(--accent)' : 'var(--mute)' }}>📶</span>
              <span class="grow" style="font-size:16px;overflow:hidden;text-overflow:ellipsis">${r.ssid}</span>
              <${Select} style="width:170px" options=${SSID_ACTIONS} value=${r.action} onChange=${(v) => act('setSSIDAction', r.id, v)} />
              <button class="icon-btn" style="color:var(--red)" aria-label=${'刪除 ' + r.ssid} onClick=${() => act('removeSSIDRule', r.id)}>${I('x')}</button></div>`)}
            <div class="row"><input class="field grow" placeholder="Wi-Fi 名稱" value=${ssidName} onInput=${(e) => setSsidName(e.target.value)} />
              <${Select} style="width:170px" options=${SSID_ACTIONS} value=${ssidAction} onChange=${setSsidAction} />
              <button class="btn primary" disabled=${!ssidName.trim()} onClick=${() => { act('addSSIDRule', ssidName, ssidAction); setSsidName(''); }}>加入</button></div>
            ${s.currentSSID && !(st.ssidRules || []).some((r) => r.ssid === s.currentSSID) && html`<div><button class="btn sm" onClick=${() => setSsidName(s.currentSSID)}>加入目前的 Wi-Fi「${s.currentSSID}」</button></div>`}`}
        <//>
        <${Section} title="網路">
          <div class="row"><span class="grow" style="font-size:17px">混合代理埠（HTTP + SOCKS5）</span><input class="field" style="width:120px" value=${mp} onInput=${(e) => setMp(e.target.value)} /></div>
          <div class="hr"></div>
          <div class="row"><span class="grow" style="font-size:17px">控制埠（API）</span><input class="field" style="width:120px" value=${cpt} onInput=${(e) => setCp(e.target.value)} /></div>
          <div class="hr"></div>
          <${ToggleRow} title="允許區域網路連線" hint="讓同一個網路的手機、電視也能用這台電腦的代理" on=${st.allowLan} onChange=${(v) => act('setSettings', { allowLan: v })} />
          <div class="hr"></div>
          <label class="lbl">延遲測試網址</label><input class="field" value=${url} onInput=${(e) => setUrl(e.target.value)} />
          <div class="row"><span class="grow"></span><button class="btn primary" onClick=${applyNet}>套用</button></div>
        <//>
      </div>
      <div style="width:460px;flex-shrink:0;display:flex;flex-direction:column;gap:20px">
        <${Section} title="更新">
          <${Info} k="Sky 版本" v=${'v' + s.appVersion} />
          ${s.appUpdate && html`<div class="row" style="background:var(--pill);border-radius:9px;padding:10px 14px;color:var(--accent)"><span class="grow">有新版 Sky ${s.appUpdate.version}</span><button class="btn sm primary" onClick=${() => act('openURL', s.appUpdate.url)}>下載</button></div>`}
          <div class="hr"></div>
          <${Info} k="mihomo 核心" v=${s.coreVersion || '—'} />
          ${s.coreUpdate && html`<div class="row" style="background:var(--pill);border-radius:9px;padding:10px 14px;color:var(--accent)"><span class="grow">有新版核心 ${s.coreUpdate.version}</span><button class="btn sm primary" disabled=${s.coreUpdating} onClick=${() => act('updateCore')}>${s.coreUpdating ? '更新中…' : '立即更新'}</button></div>`}
          <div class="hr"></div>
          <${ToggleRow} title="每天自動檢查更新" on=${st.autoCheckUpdates} onChange=${(v) => act('setSettings', { autoCheckUpdates: v })} />
          <button class="btn full" disabled=${s.checking} onClick=${() => act('checkUpdates')}>${I('refresh')}${s.checking ? '檢查中…' : '檢查 Sky 與 mihomo 更新'}</button>
        <//>
        <${Section} title="核心">
          <div class="row"><span class="grow" style="font-size:16px">狀態</span><${Tag} text=${s.coreReady ? '執行中' : '未執行'} kind=${s.coreReady ? '' : 'red'} /></div>
          <div class="hr"></div>
          <div class="row"><span class="grow" style="font-size:17px">日誌等級</span>
            <${Select} style="width:150px" options=${[['silent', '安靜'], ['error', '錯誤'], ['warning', '警告'], ['info', '資訊'], ['debug', '除錯']]} value=${st.logLevel} onChange=${(v) => act('setSettings', { logLevel: v })} /></div>
          <div class="hr"></div>
          <div class="row" style="flex-wrap:wrap;gap:10px">
            <button class="btn sm" onClick=${() => act('restartCore')}>重新啟動核心</button>
            <button class="btn sm" onClick=${async () => setLog(await act('tailLog', 400))}>查看日誌</button>
            <button class="btn sm" onClick=${() => act('openWorkDir')}>打開設定資料夾</button></div>
        <//>
        <${Section} title="關於"><${Info} k="設定資料夾" v=${s.workDir} /><//>
      </div>
    </div>
    ${log != null && html`<${Modal} title="核心日誌" onClose=${() => setLog(null)} width=${860}><pre>${log || '（沒有日誌）'}</pre><div class="row"><span class="grow"></span><button class="btn sm" onClick=${() => setLog(null)}>關閉</button></div><//>`}
  </div>`;
}

// ================= 外框 =================
const SSID_ACTIONS = [['direct', '切到直連模式'], ['rule', '切到規則模式'], ['global', '切到全域模式'], ['disconnect', '中斷系統代理']];
const PAGES = [['overview', '總覽', 'home'], ['nodes', '節點', 'server'], ['subscriptions', '訂閱', 'layers'], ['rules', '規則', 'sliders'], ['connections', '連線', 'pulse'], ['settings', '設定', 'gear']];

function App() {
  const [s, setS] = useState(null);
  const [page, setPage] = useState(new URLSearchParams(location.search).get('page') || 'overview');
  const [dismissedUpdate, setDismissed] = useState(false);
  useEffect(() => { sky.snapshot().then((x) => { PLATFORM = x.platform; setS(x); }); sky.onState((x) => setS(x)); }, []);
  if (!s) return null;
  const Page = { overview: Overview, nodes: Nodes, subscriptions: Subscriptions, rules: Rules, connections: Connections, settings: Settings }[page];
  const upd = !dismissedUpdate && (s.appUpdate || s.coreUpdate);
  return html`<div class="shell">
    <div class="drag"></div>
    <nav class="sidebar" aria-label="主選單">
      ${PAGES.map(([id, label, icon]) => html`<button class=${'nav' + (page === id ? ' on' : '')} onClick=${() => setPage(id)}>${I(icon)}${label}</button>`)}
      <div class="core-status"><span class="dot" style=${{ background: s.coreReady ? 'var(--accent)' : 'var(--red)' }}></span>${s.coreReady ? 'mihomo ' + s.coreVersion : '核心未執行'}</div>
    </nav>
    <main class="main">
      <${Page} s=${s} go=${setPage} key=${page} />
      ${s.coreError && html`<div class="banner"><span style="color:var(--amber)">⚠</span><pre>${s.coreError}</pre><button class="btn sm" onClick=${() => act('restartCore')}>重新啟動核心</button></div>`}
      ${upd && page !== 'settings' && html`<div class="banner update"><pre>${s.appUpdate ? `Sky 有新版本 ${s.appUpdate.version}` : `mihomo 核心有新版本 ${s.coreUpdate.version}`}</pre>
        <button class="btn sm primary" onClick=${() => setPage('settings')}>查看</button><button class="icon-btn" aria-label="關閉" onClick=${() => setDismissed(true)}>${I('x')}</button></div>`}
      ${s.toast && html`<div class="toast" style=${{ bottom: s.coreError ? '100px' : '24px' }}>${s.toast}</div>`}
    </main>
  </div>`;
}

render(html`<${App} />`, document.getElementById('app'));
