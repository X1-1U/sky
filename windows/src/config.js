// 把 App 裡的訂閱、規則、設定轉成 mihomo 的 config.yaml（與 Mac 版 ConfigBuilder.swift 相同邏輯）
//
// 兩種情況：
// - 有訂閱是完整設定檔（有策略組與規則）且開了「使用訂閱的分組與規則」→ 以它為底，蓋掉 Sky 要掌控的鍵，
//   自訂規則放最前面，其他訂閱與本機節點放進「其他節點」策略組
// - 否則 → 所有訂閱當節點來源，Sky 自己建「代理」「自動選擇」兩個策略組
const fs = require('fs');
const path = require('path');
const { ProfileText } = require('./profile');

const PROXY_GROUP = '代理';
const AUTO_GROUP = '自動選擇';
const EXTRA_GROUP = '其他節點';
const LOCAL = 'local';
const POLICIES = { '代理': PROXY_GROUP, '直連': 'DIRECT', '拒絕': 'REJECT', '自動選擇': AUTO_GROUP };

const q = (s) => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ') + '"';
const providerName = (sub) => 'sub-' + String(sub.id).toLowerCase();
const subFile = (sub, workDir) => path.join(workDir, 'subs', String(sub.id).toLowerCase() + '.yaml');

function providerFile(name, workDir) {
  if (name === LOCAL) return path.join(workDir, 'providers', 'local.txt');
  return path.join(workDir, 'subs', name.replace(/^sub-/, '') + '.yaml');
}

function profileSub(store, workDir) {
  return store.subscriptions.find((s) => s.enabled && s.useProfile !== false && s.isProfile && fs.existsSync(subFile(s, workDir))) || null;
}

function ruleLines(store, target) {
  const out = [];
  for (const r of store.rules) {
    if (!r.enabled) continue;
    const payload = String(r.payload || '').trim().replace(/,/g, '');
    if (!payload) continue;
    let line = `${r.type},${payload},${target(r.policy)}`;
    if (['IP-CIDR', 'IP-CIDR6', 'GEOIP'].includes(r.type)) line += ',no-resolve';
    out.push(q(line));
  }
  return out;
}

function overrides(st, tun) {
  let y = `mixed-port: ${st.mixedPort}
allow-lan: ${st.allowLan}
bind-address: "*"
mode: ${st.mode}
log-level: ${st.logLevel}
external-controller: 127.0.0.1:${st.controllerPort}
secret: ${q(st.secret)}
find-process-mode: always
profile:
  store-selected: true
`;
  if (tun) y += 'tun:\n  enable: true\n  stack: mixed\n  auto-route: true\n  auto-detect-interface: true\n  dns-hijack: ["any:53"]\n';
  return y;
}

function dnsBlock(tun) {
  let y = 'dns:\n  enable: true\n  ipv6: false\n';
  if (tun) {
    y += '  enhanced-mode: fake-ip\n  fake-ip-range: 198.18.0.1/16\n';
    y += '  fake-ip-filter: ["*.lan", "*.local", "+.msftconnecttest.com", "+.msftncsi.com", "time.*.com", "ntp.*.com", "+.pool.ntp.org"]\n';
  }
  y += '  default-nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]\n  nameserver:\n    - https://223.5.5.5/dns-query\n    - https://1.1.1.1/dns-query\n';
  return y;
}

function writeLocal(store, workDir) {
  fs.mkdirSync(path.join(workDir, 'providers'), { recursive: true });
  const links = (store.localLinks || []).map((l) => l.trim()).filter(Boolean);
  const file = providerFile(LOCAL, workDir);
  if (!links.length) { try { fs.unlinkSync(file); } catch {} return false; }
  fs.writeFileSync(file, links.join('\n'));
  return true;
}

/** 回傳 { yaml, mainGroup, autoGroup, profile } */
function build(store, workDir, { tun = false } = {}) {
  const st = store.settings;
  const hasLocal = writeLocal(store, workDir);
  const profile = profileSub(store, workDir);
  const health = `health-check: {enable: true, url: ${q(st.testURL)}, interval: 600, lazy: true}`;

  const names = store.subscriptions
    .filter((s) => s.enabled && s.id !== profile?.id && fs.existsSync(subFile(s, workDir)))
    .map(providerName);
  if (hasLocal) names.push(LOCAL);
  const entry = (n) => `${q(n)}: {type: file, path: ${n === LOCAL ? './providers/local.txt' : './subs/' + n.replace(/^sub-/, '') + '.yaml'}, ${health}}`;

  if (profile) {
    const p = new ProfileText(fs.readFileSync(subFile(profile, workDir), 'utf8'));
    p.strip();
    const groups = p.groupNames();
    const main = (profile.mainGroup && groups.includes(profile.mainGroup)) ? profile.mainGroup : (groups[0] || 'DIRECT');
    const auto = groups.find((g) => /自动|自動|auto/i.test(g)) || main;
    const target = (pol) => ({ '代理': main, '自動選擇': auto, '直連': 'DIRECT', '拒絕': 'REJECT' })[pol] || main;
    if (names.length) {
      p.addMapEntries(names.map(entry), 'proxy-providers');
      p.appendItems([`{name: ${q(EXTRA_GROUP)}, type: select, use: [${names.map(q).join(', ')}]}`], 'proxy-groups');
    }
    p.prependItems(ruleLines(store, target), 'rules');
    let y = `# 由 Sky 產生：以訂閱「${profile.name}」為底稿，Sky 蓋掉埠口、控制 API、TUN 等設定\n`;
    y += p.text + '\n\n# ---- Sky ----\n' + overrides(st, tun);
    if (!p.has('dns')) y += dnsBlock(tun);
    return { yaml: y, mainGroup: main, autoGroup: auto, profile };
  }

  let y = '# 由 Sky 自動產生，手動修改會被覆蓋\n' + overrides(st, tun);
  y += 'ipv6: false\nunified-delay: true\ntcp-concurrent: true\ngeo-auto-update: false\n' + dnsBlock(tun);
  if (names.length) y += 'proxy-providers:\n' + names.map((n) => '  ' + entry(n) + '\n').join('');
  const use = names.map(q).join(', ');
  y += 'proxy-groups:\n';
  if (!names.length) y += `  - {name: ${q(PROXY_GROUP)}, type: select, proxies: [DIRECT]}\n`;
  else {
    y += `  - {name: ${q(PROXY_GROUP)}, type: select, proxies: [${q(AUTO_GROUP)}], use: [${use}]}\n`;
    y += `  - {name: ${q(AUTO_GROUP)}, type: url-test, use: [${use}], url: ${q(st.testURL)}, interval: 300, tolerance: 50, lazy: true}\n`;
  }
  const target = (p) => (p === '自動選擇' && !names.length) ? PROXY_GROUP : (POLICIES[p] || PROXY_GROUP);
  y += 'rules:\n' + ruleLines(store, target).map((l) => `  - ${l}\n`).join('');
  y += `  - ${q('MATCH,' + target(st.defaultPolicy))}\n`;
  return { yaml: y, mainGroup: PROXY_GROUP, autoGroup: names.length ? AUTO_GROUP : PROXY_GROUP, profile: null };
}

module.exports = { build, providerName, providerFile, subFile, profileSub, PROXY_GROUP, AUTO_GROUP, EXTRA_GROUP, LOCAL };
