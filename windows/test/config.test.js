// Windows 版設定檔產生器的測試；測試檔與 Mac 版共用（../Tests/fixtures）
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const { ProfileText, STRIPPED } = require('../src/profile');
const config = require('../src/config');

const fixture = (n) => fs.readFileSync(path.join(__dirname, '..', '..', 'Tests', 'fixtures', n), 'utf8');
const SUB = '11111111-2222-4333-8444-555555555555';
const OTHER = '66666666-7777-4888-8999-000000000000';

function makeStore(dir, { allowLan = false, other = false, local = false } = {}) {
  fs.mkdirSync(path.join(dir, 'subs'), { recursive: true });
  const subs = [{ id: SUB, name: '主訂閱', url: 'https://sub.example.invalid/a', enabled: true, useProfile: true, isProfile: true }];
  fs.writeFileSync(config.subFile(subs[0], dir), fixture('profile-full.yaml'));
  if (other) {
    subs.push({ id: OTHER, name: '其他', url: 'https://sub.example.invalid/b', enabled: true });
    fs.writeFileSync(config.subFile(subs[1], dir), fixture('nodes-only.yaml'));
  }
  return {
    subscriptions: subs,
    rules: [{ id: 'r1', type: 'DOMAIN-SUFFIX', payload: 'example.com', policy: '代理', enabled: true }],
    localLinks: local ? [fixture('local-links.txt').trim()] : [],
    settings: {
      mixedPort: 7899, controllerPort: 9099, secret: 'testsecret', allowLan, logLevel: 'info', mode: 'rule',
      defaultPolicy: '代理', testURL: 'https://www.gstatic.com/generate_204', lanUser: 'sky', lanPassword: 'pw123456abcd',
    },
  };
}
const tmpdir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'skytest-'));

test('解析策略組、規則與內嵌節點', () => {
  const p = new ProfileText(fixture('profile-full.yaml'));
  assert.deepStrictEqual(p.groupNames(), ['默认代理', 'AI', '全部手动', '全部自动', '香港故转']);
  assert.strictEqual(p.rules().length, 4);
  assert.strictEqual(p.inlineProxyCount, 2);
  assert.ok(p.isFullProfile);
  assert.ok(!new ProfileText(fixture('nodes-only.yaml')).isFullProfile);
});

test('拿掉 Sky 掌控的段落、保留其他', () => {
  const p = new ProfileText(fixture('profile-full.yaml'));
  p.strip(STRIPPED);
  for (const k of ['mixed-port', 'authentication', 'skip-auth-prefixes', 'external-controller', 'secret', 'tun', 'external-ui', 'allow-lan']) assert.ok(!p.has(k), k);
  for (const k of ['rule-anchor', 'proxy-providers', 'dns', 'proxy-groups', 'rules', 'rule-providers']) assert.ok(p.has(k), k);
});

test('設定檔模式：自訂規則在最前面、控制 API 被蓋掉', () => {
  const dir = tmpdir();
  const b = config.build(makeStore(dir), dir);
  assert.strictEqual(b.mainGroup, '默认代理');
  assert.ok(b.yaml.indexOf('"DOMAIN-SUFFIX,example.com,默认代理"') < b.yaml.indexOf('RULE-SET,private_domain'));
  assert.ok(b.yaml.includes('external-controller: 127.0.0.1:9099'));
  assert.ok(!b.yaml.includes('0.0.0.0:9090'));
});

test('區網關閉時拿掉訂閱帳密；開啟時改用 Sky 的帳密、本機免密碼', () => {
  const dir = tmpdir();
  const off = config.build(makeStore(dir), dir).yaml;
  assert.ok(!off.includes('user:secretpass') && !off.includes('authentication:'));
  const on = config.build(makeStore(dir, { allowLan: true }), dir).yaml;
  assert.ok(on.includes('authentication:\n  - "sky:pw123456abcd"'));
  assert.ok(on.includes('skip-auth-prefixes:\n  - 127.0.0.1/8'));
  assert.ok(!on.includes('user:secretpass'));
});

test('TUN 區塊取代訂閱自己的 tun', () => {
  const dir = tmpdir();
  const y = config.build(makeStore(dir), dir, { tun: true }).yaml;
  assert.ok(y.includes('tun:\n  enable: true\n  stack: mixed'));
  assert.ok(!y.includes('stack: system'));
});

test('產生的設定 mihomo 都接受', (t) => {
  const exe = process.platform === 'win32' ? 'mihomo.exe' : 'mihomo';
  const bin = process.env.MIHOMO_BIN
    || [path.join(__dirname, '..', 'vendor', exe), path.join(__dirname, '..', '..', 'vendor', 'mihomo')].find((f) => fs.existsSync(f));
  if (!bin) return t.skip('找不到 mihomo');
  const dir = tmpdir();
  const variants = {
    profile: config.build(makeStore(dir), dir).yaml,
    lan: config.build(makeStore(dir, { allowLan: true, other: true, local: true }), dir).yaml,
    tun: config.build(makeStore(dir, { other: true }), dir, { tun: true }).yaml,
  };
  for (const [name, yaml] of Object.entries(variants)) {
    const f = path.join(dir, name + '.yaml');
    fs.writeFileSync(f, yaml);
    const r = cp.spawnSync(bin, ['-t', '-d', dir, '-f', f], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, `${name}：${(r.stdout + r.stderr).slice(-300)}`);
  }
});
