#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_frida.py — 一条命令完成：找设备 / 找 App / 注入 / 抓密码 / 拉回日志

用法:
  python run_frida.py list                     列出可用设备
  python run_frida.py apps                     列出设备上的 App（找 bundle id）
  python run_frida.py run <bundleid>           拉起 App 并注入 frida_sutu.js
  python run_frida.py attach <进程名或pid>      注入到已运行进程

连接方式:
  --usb          (默认) 用 USB
  --host IP:PORT 用远程 frida-server（SSH 隧道场景）
"""
import argparse
import os
import sys
import time

import frida

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "frida_sutu.js")


def get_device(args):
    mgr = frida.get_device_manager()
    if args.host:
        dev = mgr.add_remote_device(args.host)
        print(f"[+] remote device {args.host}")
        return dev
    devs = [d for d in mgr.enumerate_devices() if d.type == "usb"]
    if not devs:
        print("[!] 没有发现 USB 设备。检查：")
        print("    1) 数据线已插、手机已信任此电脑")
        print("    2) 设备已装 Frida（Sileo 源 https://build.frida.re）")
        print("    3) rootless 越狱需装 frida rootless 版本")
        print("    4) 或改用 --host 走 SSH 隧道：")
        print("       ssh -L 27042:127.0.0.1:27042 root@<设备IP>")
        print("       python run_frida.py --host 127.0.0.1:27042 run <bundleid>")
        sys.exit(2)
    print(f"[+] usb device: {devs[0].name}")
    return devs[0]


def cmd_list(args):
    for d in frida.get_device_manager().enumerate_devices():
        print(f"{d.id:20s} {d.type:10s} {d.name}")


def cmd_apps(args):
    dev = get_device(args)
    apps = dev.enumerate_applications()
    key = (args.filter or "").lower()
    print(f"{'identifier':45s} {'pid':>7s}  name")
    for a in sorted(apps, key=lambda x: x.identifier):
        if key and key not in a.identifier.lower() and key not in a.name.lower():
            continue
        print(f"{a.identifier:45s} {a.pid:>7d}  {a.name}")


def on_message(msg, data):
    if msg.get("type") == "send":
        print("[js]", msg.get("payload"))
    elif msg.get("type") == "error":
        print("[js-error]", msg.get("stack") or msg.get("description"))


def cmd_run(args):
    if not os.path.isfile(SCRIPT):
        print(f"[!] 找不到 {SCRIPT}")
        sys.exit(2)
    src = open(SCRIPT, encoding="utf-8").read()
    dev = get_device(args)
    print(f"[+] spawn {args.target}")
    pid = dev.spawn([args.target])
    session = dev.attach(pid)
    script = session.create_script(src)
    script.on("message", on_message)
    script.load()
    dev.resume(pid)
    print("[+] resumed, 等待 hook ... (Ctrl+C 结束)")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[+] detach")


def cmd_attach(args):
    src = open(SCRIPT, encoding="utf-8").read()
    dev = get_device(args)
    target = args.target
    if target.isdigit():
        target = int(target)
    session = dev.attach(target)
    script = session.create_script(src)
    script.on("message", on_message)
    script.load()
    print("[+] attached, Ctrl+C 结束")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--usb", action="store_true")
    ap.add_argument("--host", default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    p_apps = sub.add_parser("apps")
    p_apps.add_argument("filter", nargs="?", default=None)
    p_run = sub.add_parser("run")
    p_run.add_argument("target")
    p_att = sub.add_parser("attach")
    p_att.add_argument("target")
    args = ap.parse_args()

    {"list": cmd_list, "apps": cmd_apps, "run": cmd_run, "attach": cmd_attach}[args.cmd](args)


if __name__ == "__main__":
    main()
