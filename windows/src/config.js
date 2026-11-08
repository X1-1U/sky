// 把 App 裡的訂閱、規則、設定轉成 mihomo 的 config.yaml（與 Mac 版 ConfigBuilder.swift 相同邏輯）
const fs = require('fs');
const path = require('path');

const PROXY_GROUP = '代理';
const AUTO_GROUP = '自動選擇';
const LOCAL = 'local';

const POLICIES = {
  '代理': PROXY_GROUP,
  '直連': 'DIRECT',
  '拒絕': 'REJECT',
  '自動選擇': AUTO_GROUP,
};

const q = (s) => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ') + '"';

function providerName(sub) { return 'sub-' + String(sub.id).toLowerCase(); }

function providerFile(name, workDir) {
  return path.join(workDir, 'providers', name + (name === LOCAL ? '.txt' : '.yaml'));
}

function build(store, workDir, { tun = false } = {}) {
  const st = store.settings;
  fs.mkdirSync(path.join(workDir, 'providers'), { recursive: true });

  const names = [];
  let providers = '';
  const health = `    health-check:\n      enable: true\n      url: ${q(st.testURL)}\n      interval: 600\n      lazy: true\n`;

  for (const sub of store.subscriptions) {
    if (!sub.enabled) continue;
    const url = (sub.url || '').trim();
    if (!url) continue;
    const name = providerName(sub);
    const cached = fs.existsSync(providerFile(name, workDir));
    names.push(name);
    providers += `  ${q(name)}:\n    type: http\n    url: ${q(url)}\n    path: ./providers/${name}.yaml\n`;
    providers += `    interval: ${sub.autoUpdate ? Math.max(1, sub.intervalHours) * 3600 : 0}\n`;
    // 第一次下載時還沒有節點可用，只能直連
    providers += `    proxy: ${sub.viaProxy && cached ? q(PROXY_GROUP) : 'DIRECT'}\n` + health;
  }

  const links = (store.localLinks || []).map((l) => l.trim()).filter(Boolean);
  const localFile = providerFile(LOCAL, workDir);
  if (links.length === 0) {
    try { fs.unlinkSync(localFile); } catch {}
  } else {
    fs.writeFileSync(localFile, links.join('\n'));
    names.push(LOCAL);
    providers += `  ${LOCAL}:\n    type: file\n    path: ./providers/${LOCAL}.txt\n` + health;
  }

  let y = `# 由 Sky 自動產生，手動修改會被覆蓋
mixed-port: ${st.mixedPort}
allow-lan: ${st.allowLan}
bind-address: "*"
mode: ${st.mode}
log-level: ${st.logLevel}
ipv6: false
external-controller: 127.0.0.1:${st.controllerPort}
secret: ${q(st.secret)}
find-process-mode: always
unified-delay: true
tcp-concurrent: true
geo-auto-update: false
profile:
  store-selected: true
`;

  if (tun) {
    y += `tun:
  enable: true
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  dns-hijack: ["any:53"]
`;
  }

  y += `dns:
  enable: true
  ipv6: false
`;
  if (tun) {
    y += `  listen: 127.0.0.1:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter: ["*.lan", "*.local", "+.msftconnecttest.com", "+.msftncsi.com", "time.*.com", "ntp.*.com", "+.pool.ntp.org"]
`;
  }
  y += `  default-nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]
  nameserver:
    - https://223.5.5.5/dns-query
    - https://1.1.1.1/dns-query
`;

  if (providers) y += 'proxy-providers:\n' + providers;

  const use = names.map(q).join(', ');
  y += 'proxy-groups:\n';
  if (names.length === 0) {
    y += `  - name: ${q(PROXY_GROUP)}\n    type: select\n    proxies: [DIRECT]\n`;
  } else {
    y += `  - name: ${q(PROXY_GROUP)}\n    type: select\n    proxies: [${q(AUTO_GROUP)}]\n    use: [${use}]\n`;
    y += `  - name: ${q(AUTO_GROUP)}\n    type: url-test\n    use: [${use}]\n    url: ${q(st.testURL)}\n    interval: 300\n    tolerance: 50\n    lazy: true\n`;
  }

  const target = (p) => (p === '自動選擇' && names.length === 0) ? PROXY_GROUP : (POLICIES[p] || PROXY_GROUP);

  y += 'rules:\n';
  for (const r of store.rules) {
    if (!r.enabled) continue;
    const payload = String(r.payload || '').trim().replace(/,/g, '');
    if (!payload) continue;
    let line = `${r.type},${payload},${target(r.policy)}`;
    if (['IP-CIDR', 'IP-CIDR6', 'GEOIP'].includes(r.type)) line += ',no-resolve';
    y += `  - ${q(line)}\n`;
  }
  y += `  - ${q('MATCH,' + target(st.defaultPolicy))}\n`;
  return y;
}

module.exports = { build, providerName, providerFile, PROXY_GROUP, AUTO_GROUP, LOCAL };
