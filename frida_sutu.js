/*
 * SutuDump v2 — Frida 版（零编译，直接跑）
 *
 * 用法：
 *   frida -U -f com.xxx.sutuplus -l frida_sutu.js --no-pause
 *   frida -U -n SutuPLUS -l frida_sutu.js
 *
 * 输出（设备上）：
 *   /var/mobile/Documents/sutu_dump/pwd.txt            一行一个密码（去重）
 *   /var/mobile/Documents/sutu_dump/raw/*.rbt          抓到的外层包
 *   /var/mobile/Documents/sutu_dump/out/<pwd前6位>/    自动拆好的 PNG
 */

const ROOT = '/var/mobile/Documents/sutu_dump';
const INNER_PW = '2E@Qws#b9MQ6p4^sRS';
let seen = new Set();
let pwds = [];
let inUnpack = false;

function NS(s) { return ObjC.classes.NSString.stringWithString_(s); }
function nsToJs(nsstr) {
  try { return new ObjC.Object(nsstr).toString(); } catch (e) { return null; }
}

function mkdir(p) {
  ObjC.classes.NSFileManager.defaultManager()
    .createDirectoryAtPath_withIntermediateDirectories_attributes_error_(NS(p), 1, NULL, NULL);
}

function appendFile(path, text) {
  const fm = ObjC.classes.NSFileManager.defaultManager();
  if (!fm.fileExistsAtPath_(NS(path))) {
    ObjC.classes.NSData.dataWithBytes_length_(text, text.length).writeToFile_atomically_(NS(path), 1);
    return;
  }
  const old = ObjC.classes.NSString.stringWithContentsOfFile_encoding_error_(NS(path), 4, NULL);
  const merged = (old.isNull() ? '' : old.toString()) + text;
  ObjC.classes.NSData.dataWithBytes_length_(merged, merged.length).writeToFile_atomically_(NS(path), 1);
}

function logPwd(pwd, src) {
  if (!pwd || pwd.length < 6 || seen.has(pwd)) return;
  seen.add(pwd);
  pwds.push(pwd);
  appendFile(ROOT + '/pwd.txt', pwd + '\t' + src + '\n');
  console.log('[SUTU] PWD ' + pwd + '  (' + src + ')');
}

function isZip(nsdata) {
  try {
    const len = nsdata.length();
    if (len < 4) return false;
    const p = nsdata.bytes();
    const b = Memory.readByteArray(p, 2);
    const u = new Uint8Array(b);
    return u[0] === 0x50 && u[1] === 0x4b;
  } catch (e) { return false; }
}

function unpack(dataObj, hint, outDir, depth) {
  if (depth > 4 || inUnpack) return;
  inUnpack = true;
  try {
    mkdir(outDir);
    const tmp = ROOT + '/tmp_' + depth + '_' + Date.now() + '.zip';
    if (!dataObj.writeToFile_atomically_(NS(tmp), 1)) return;

    const ZZArchive = ObjC.classes.ZZArchive;
    if (!ZZArchive) { console.log('[SUTU] no ZZArchive'); return; }
    const url = ObjC.classes.NSURL.fileURLWithPath_(NS(tmp));
    const archive = ZZArchive.archiveWithURL_error_(url, NULL);
    if (archive.isNull()) return;

    const cands = [];
    if (hint) cands.push(hint);
    pwds.forEach(p => { if (!cands.includes(p)) cands.push(p); });
    if (!cands.includes(INNER_PW)) cands.push(INNER_PW);

    let entries = null, used = null;
    for (const p of cands) {
      let r = null;
      try {
        if (archive.respondsToSelector_(ObjC.selector('newEntriesWithPassword:error:'))) {
          r = archive.newEntriesWithPassword_error_(NS(p), NULL);
        } else {
          r = archive.entriesWithPassword_error_(NS(p), NULL);
        }
      } catch (e) { r = null; }
      if (r && !r.isNull() && r.count() > 0) { entries = r; used = p; break; }
    }
    if (!entries) { console.log('[SUTU] unpack: no matching password'); return; }

    const n = entries.count();
    for (let i = 0; i < n; i++) {
      const entry = entries.objectAtIndex_(i);
      let name = null;
      try { name = nsToJs(entry.valueForKey_(NS('fileName'))); } catch (e) {}
      if (!name) continue;
      let d = null;
      try { d = entry.newDataWithPassword_error_(NS(used), NULL); } catch (e) { d = null; }
      if (!d || d.isNull()) continue;

      const safe = name.replace(/[\/\\:*?"<>|]/g, '_');
      if (isZip(d)) {
        unpack(d, null, outDir + '/' + safe.replace(/\.rbt$/i, '') + '_x', depth + 1);
      } else {
        d.writeToFile_atomically_(NS(outDir + '/' + safe), 1);
      }
    }
    console.log('[SUTU] unpacked ' + n + ' entries -> ' + outDir);
    ObjC.classes.NSFileManager.defaultManager().removeItemAtPath_error_(NS(tmp), NULL);
  } catch (e) {
    console.log('[SUTU] unpack error: ' + e);
  } finally {
    inUnpack = false;
  }
}

function hookPasswordMethod(clsName, tag) {
  const cls = ObjC.classes[clsName];
  if (!cls) { console.log('[SUTU] missing class ' + clsName); return; }
  const m = cls['- newDataWithPassword:error:'];
  if (!m) { console.log('[SUTU] missing method on ' + clsName); return; }
  Interceptor.attach(m.implementation, {
    onEnter(args) { this.pwd = args[2]; },
    onLeave(retval) {
      if (inUnpack) return;
      try {
        const pwd = this.pwd.isNull() ? null : new ObjC.Object(this.pwd).toString();
        if (!pwd) return;
        logPwd(pwd, tag);
        if (!retval.isNull()) {
          const d = new ObjC.Object(retval);
          if (isZip(d)) {
            const keep = d.retain();
            const dir = ROOT + '/out/' + pwd.substring(0, 6);
            setTimeout(() => { unpack(new ObjC.Object(keep), pwd, dir, 0); }, 0);
          }
        }
      } catch (e) { console.log('[SUTU] hook err ' + e); }
    }
  });
  console.log('[SUTU] hooked ' + clsName);
}

// 抓接口返回里的密码候选（不用下载主题，打开商店页就可能命中）
function hookJSON() {
  const J = ObjC.classes.NSJSONSerialization;
  if (!J) return;
  const m = J['+ JSONObjectWithData:options:error:'];
  if (!m) return;
  Interceptor.attach(m.implementation, {
    onLeave(retval) {
      try {
        if (retval.isNull()) return;
        const s = new ObjC.Object(retval).description().toString();
        if (!s || s.length < 20) return;
        const re = /[A-Za-z0-9^$._!@#%&*()\-]{18,64}/g;
        let mm;
        while ((mm = re.exec(s)) !== null) {
          const c = mm[0];
          if (/\d/.test(c) && /[A-Za-z]/.test(c)) logPwd(c, 'JSON');
        }
      } catch (e) {}
    }
  });
  console.log('[SUTU] hooked NSJSONSerialization');
}

function main() {
  mkdir(ROOT);
  mkdir(ROOT + '/out');
  mkdir(ROOT + '/raw');
  hookPasswordMethod('ZZOldArchiveEntry', 'ZZOld');
  hookPasswordMethod('ZZNewArchiveEntry', 'ZZNew');
  hookJSON();
  console.log('[SUTU] ready, output -> ' + ROOT);
}

setImmediate(main);
