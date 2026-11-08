// 用文字方式處理訂閱的 mihomo 設定檔（保留錨點、註解與原本格式），與 Mac 版 Profile.swift 相同邏輯

const STRIPPED = new Set([
  'port', 'socks-port', 'redir-port', 'tproxy-port', 'mixed-port', 'authentication', 'skip-auth-prefixes',
  'allow-lan', 'bind-address', 'lan-allowed-ips', 'lan-disallowed-ips', 'mode', 'log-level',
  'external-controller', 'external-controller-tls', 'external-controller-unix', 'external-controller-pipe',
  'external-controller-cors', 'external-ui', 'external-ui-name', 'external-ui-url', 'external-doh-server',
  'secret', 'tun', 'profile', 'find-process-mode', 'interface-name', 'routing-mark',
]);

class ProfileText {
  constructor(text) { this.lines = String(text).replace(/\r\n/g, '\n').split('\n'); }
  get text() { return this.lines.join('\n'); }

  static topKey(line) {
    if (!line || ' \t#-'.includes(line[0])) return null;
    const m = line.match(/^([A-Za-z0-9_.-]+):/);
    return m ? m[1] : null;
  }

  blocks() {
    const out = [];
    this.lines.forEach((l, i) => {
      const k = ProfileText.topKey(l);
      if (k) { if (out.length) out[out.length - 1].end = i; out.push({ key: k, start: i, end: this.lines.length }); }
    });
    return out;
  }
  block(key) { return this.blocks().find((b) => b.key === key); }
  has(key) { return !!this.block(key); }

  strip(keys = STRIPPED) {
    for (const b of this.blocks().reverse()) if (keys.has(b.key)) this.lines.splice(b.start, b.end - b.start);
  }

  items(key) {
    const b = this.block(key);
    if (!b) return [];
    const inline = this.lines[b.start].match(/:\s*\[(.*)\]\s*$/);
    if (inline) return inline[1].split(',').map((x) => x.trim()).filter(Boolean);
    const out = []; let ind = null;
    for (const l of this.lines.slice(b.start + 1, b.end)) {
      const t = l.trim();
      if (!t || t.startsWith('#') || !(t.startsWith('- ') || t === '-')) continue;
      const n = l.length - l.trimStart().length;
      if (ind === null) ind = n;
      if (n === ind) out.push(t.slice(2));
    }
    return out;
  }

  childIndent(b) {
    for (const l of this.lines.slice(b.start + 1, b.end)) {
      const t = l.trim();
      if (!t || t.startsWith('#')) continue;
      return l.slice(0, l.length - l.trimStart().length);
    }
    return '  ';
  }

  prependItems(items, key) {
    if (!items.length) return;
    const b = this.block(key);
    if (!b) { this.lines.push(key + ':', ...items.map((x) => '  - ' + x)); return; }
    const ind = this.childIndent(b);
    this.lines.splice(b.start + 1, 0, ...items.map((x) => `${ind}- ${x}`));
  }

  appendItems(items, key) {
    if (!items.length) return;
    const b = this.block(key);
    if (!b) { this.lines.push(key + ':', ...items.map((x) => '  - ' + x)); return; }
    const ind = this.childIndent(b);
    let at = b.end;
    while (at > b.start + 1 && !this.lines[at - 1].trim()) at--;
    this.lines.splice(at, 0, ...items.map((x) => `${ind}- ${x}`));
  }

  addMapEntries(entries, key) {
    if (!entries.length) return;
    const b = this.block(key);
    if (!b) { this.lines.push(key + ':', ...entries.map((x) => '  ' + x)); return; }
    const ind = this.childIndent(b);
    this.lines.splice(b.start + 1, 0, ...entries.map((x) => ind + x));
  }

  static nameOf(item) {
    const s = item.startsWith('{') ? item.slice(1) : item;
    const m = s.match(/name:\s*(?:"([^"]*)"|'([^']*)'|([^,}]+))/);
    if (!m) return null;
    return (m[1] ?? m[2] ?? m[3] ?? '').trim() || null;
  }

  groupNames() { return this.items('proxy-groups').map(ProfileText.nameOf).filter(Boolean); }
  rules() { return this.items('rules').map((r) => r.replace(/^["'\s]+|["'\s]+$/g, '')); }
  get isFullProfile() { return this.groupNames().length > 0 && this.rules().length > 0; }
  get inlineProxyCount() { return this.items('proxies').length; }
}

module.exports = { ProfileText, STRIPPED };
