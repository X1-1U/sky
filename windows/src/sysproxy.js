// 系統代理：Windows 寫登錄檔＋通知 WinINet；Mac（只用於開發測試）用 networksetup
const { execFile } = require('child_process');

const IS_WIN = process.platform === 'win32';
const KEY = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings';
const BYPASS = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>';

function run(cmd, args) {
  return new Promise((resolve) => {
    execFile(cmd, args, { windowsHide: true }, (err, stdout) => resolve({ ok: !err, out: String(stdout || '') }));
  });
}

// 讓已開啟的程式（瀏覽器等）立刻套用新的代理設定
const REFRESH_PS = `$s='[DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr h,int o,IntPtr b,int l);';` +
  `$t=Add-Type -MemberDefinition $s -Name W -Namespace SkyProxy -PassThru;` +
  `[void]$t::InternetSetOption(0,39,0,0);[void]$t::InternetSetOption(0,37,0,0)`;

async function refreshWin() {
  await run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', REFRESH_PS]);
}

async function macServices() {
  const { out } = await run('/usr/sbin/networksetup', ['-listallnetworkservices']);
  return out.split('\n').slice(1).filter((s) => s && !s.startsWith('*'));
}

async function enable(port) {
  if (IS_WIN) {
    await run('reg', ['add', KEY, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    await run('reg', ['add', KEY, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', `127.0.0.1:${port}`, '/f']);
    await run('reg', ['add', KEY, '/v', 'ProxyOverride', '/t', 'REG_SZ', '/d', BYPASS, '/f']);
    await refreshWin();
  } else {
    for (const s of await macServices()) {
      await run('/usr/sbin/networksetup', ['-setwebproxy', s, '127.0.0.1', String(port)]);
      await run('/usr/sbin/networksetup', ['-setsecurewebproxy', s, '127.0.0.1', String(port)]);
      await run('/usr/sbin/networksetup', ['-setsocksfirewallproxy', s, '127.0.0.1', String(port)]);
    }
  }
}

async function disable() {
  if (IS_WIN) {
    await run('reg', ['add', KEY, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    await refreshWin();
  } else {
    for (const s of await macServices()) {
      await run('/usr/sbin/networksetup', ['-setwebproxystate', s, 'off']);
      await run('/usr/sbin/networksetup', ['-setsecurewebproxystate', s, 'off']);
      await run('/usr/sbin/networksetup', ['-setsocksfirewallproxystate', s, 'off']);
    }
  }
}

/** 系統代理是否正指向這個埠 */
async function isPointing(port) {
  if (IS_WIN) {
    const a = await run('reg', ['query', KEY, '/v', 'ProxyEnable']);
    const b = await run('reg', ['query', KEY, '/v', 'ProxyServer']);
    return /0x1\b/.test(a.out) && b.out.includes(`127.0.0.1:${port}`);
  }
  const s = (await macServices())[0];
  if (!s) return false;
  const { out } = await run('/usr/sbin/networksetup', ['-getwebproxy', s]);
  return out.includes('Enabled: Yes') && out.includes('Server: 127.0.0.1') && out.includes(`Port: ${port}`);
}

/** Windows：目前是否以系統管理員身分執行 */
async function isAdmin() {
  if (!IS_WIN) return false;
  const { ok } = await run('net', ['session']);
  return ok;
}

module.exports = { enable, disable, isPointing, isAdmin, run };
