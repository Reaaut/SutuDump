# -*- coding: utf-8 -*-
"""
auto_unpack.py —— 微信主题 .rbt 自动解包

用法:
  python auto_unpack.py --rbt <Assets.rbt> --out <输出目录> [--log <log.txt>] [--pwd <密码> ...]

流程:
  1. 从 log 里抓所有非 (nil) 的 newDataWithPassword pwd=[...]
  2. 对目标文件逐层尝试: 无密码 -> 候选密码
  3. 每层若是 ZIP 就继续往里拆, 直到拆出真实文件
"""
import argparse, os, re, shutil, sys, zipfile

def collect_passwords(log_path, extra):
    pwds = []
    for p in extra or []:
        if p not in pwds:
            pwds.append(p)
    if log_path and os.path.isfile(log_path):
        raw = open(log_path, 'rb').read().decode('utf-8', 'replace')
        for m in re.finditer(r'pwd=\[([^\]]*)\]', raw):
            v = m.group(1)
            if v in ('(nil)', 'nil', ''):
                continue
            if v not in pwds:
                pwds.append(v)
    return pwds

def is_zip(path):
    with open(path, 'rb') as f:
        head = f.read(4)
    return head[:2] == b'PK'

def open_zip(path, pwds):
    """返回 (zf, 使用的密码) ；成功即返回"""
    if not is_zip(path):
        return None, None
    zf = zipfile.ZipFile(path)
    infos = [i for i in zf.infolist() if not i.is_dir()]
    if not infos:
        return zf, None
    # 无密码
    try:
        zf.read(infos[0], pwd=None)
        return zf, None
    except Exception:
        pass
    if not any(i.flag_bits & 1 for i in infos):
        return zf, None
    for p in pwds:
        try:
            zf.read(infos[0], pwd=p.encode('utf-8') if isinstance(p, str) else p)
            return zf, p
        except Exception:
            continue
    return zf, False   # 加密但密码都没中

def unpack(path, pwds, outdir, depth=0, tag='layer'):
    os.makedirs(outdir, exist_ok=True)
    if not is_zip(path):
        dst = os.path.join(outdir, os.path.basename(path))
        shutil.copy2(path, dst)
        print(f"[{tag}] 非 ZIP, 直接输出: {dst} ({os.path.getsize(dst)} bytes)")
        return True

    zf, pw = open_zip(path, pwds)
    if pw is False:
        print(f"[{tag}] 加密但候选密码都不匹配; 候选={pwds}")
        return False
    print(f"[{tag}] ZIP 打开成功, 条目={len(zf.infolist())}, 密码={pw or '(无)'}")

    infos = zf.infolist()
    real_dirs = set()
    for i in infos:
        if i.is_dir():
            continue
        name = i.filename.replace('/', os.sep)
        target = os.path.join(outdir, name)
        os.makedirs(os.path.dirname(target) or outdir, exist_ok=True)
        with zf.open(i, pwd=pw.encode('utf-8') if isinstance(pw, str) else pw) as f, open(target, 'wb') as o:
            o.write(f.read())

    # 检查解出的东西里还有没有嵌套 ZIP
    for i in infos:
        if i.is_dir():
            continue
        target = os.path.join(outdir, i.filename.replace('/', os.sep))
        if is_zip(target):
            sub = os.path.join(outdir, '_' + os.path.splitext(os.path.basename(target))[0] + '_unpacked')
            ok = unpack(target, pwds, sub, depth + 1, tag=f'{tag}.{depth+1}')
            if not ok:
                print(f"[{tag}] 嵌套层未解开: {target}")
    return True

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rbt', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--log', default=None)
    ap.add_argument('--pwd', action='append', default=[])
    a = ap.parse_args()

    pwds = collect_passwords(a.log, a.pwd)
    print("候选密码:", pwds if pwds else "(无)")
    ok = unpack(a.rbt, pwds, a.out, 0, 'layer0')

    files = [os.path.join(r, f) for r, _, fs in os.walk(a.out) for f in fs]
    print(f"\n完成: {len(files)} 个文件, 共 {sum(os.path.getsize(f) for f in files)} bytes -> {a.out}")
    sys.exit(0 if ok else 2)

if __name__ == '__main__':
    main()
