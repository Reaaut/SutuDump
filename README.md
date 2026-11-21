# SutuDump v2

微信主题包（`.rbt` / `Assets.rbt`）密码抓取 + 自动解包。

## 两种用法

### A. Frida（零编译，立刻用）

```bash
frida -U -f <AppBundleID> -l frida_sutu.js --no-pause
```

或已运行：

```bash
frida -U -n <进程名> -l frida_sutu.js
```

打开主题商店页 / 导入主题，日志里出现：

```
[SUTU] PWD xxxxxxxx  (ZZOld)
[SUTU] unpacked 1551 entries -> /var/mobile/Documents/sutu_dump/out/xxxxxx
```

产物：

```
/var/mobile/Documents/sutu_dump/
├─ pwd.txt             一行一个密码（去重）
├─ raw/                抓到的外层 rbt
└─ out/<pwd前6位>/     自动拆好的 PNG（外层+内层递归拆完）
```

### B. 编译成 dylib

```bash
export THEOS=~/theos
make clean
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

安装：

```bash
scp packages/*.deb root@device:/var/root/
ssh root@device "dpkg -i /var/root/*.deb && killall -9 SpringBoard"
```

仓库自带 `.github/workflows/build.yml`，push 后 GitHub Actions 会自动编出 deb 和 dylib 作为 Artifacts。

## 注入目标

`SutuDump.plist` 里的 `Bundles` 要填目标 App 的 bundle id：

```
Filza → /var/containers/Bundle/Application/<UUID>/xxx.app/Info.plist → CFBundleIdentifier
```

## hook 点

| 类 / 方法 | 作用 |
|---|---|
| `ZZOldArchiveEntry -newDataWithPassword:error:` | 主密码来源（外层 rbt） |
| `ZZNewArchiveEntry -newDataWithPassword:error:` | 新格式条目 |
| `NSJSONSerialization +JSONObjectWithData:options:error:` | 从接口响应里捞密码（不用下载主题） |
| `NSUserDefaults -objectForKey:` (`ThemeCurentAssetFloderNameKey`) | 记录主题缓存路径 |

所有 ZipZap 的 selector 都通过 `NSSelectorFromString` + `objc_msgSend` 调用，不依赖 ZipZap 头文件，兼容新旧 API 命名。

## 方案 B2：不下载也能触发

1. 打开 App 进一次主题页 → `theme_folder.txt` 里出现真实缓存路径
2. 把别人发你的 `.rbt` 改名 `Assets.rbt`，塞进该主题目录
3. 回 App 点这个主题的**预览**（不点应用）
4. `pwd.txt` 多一行，`out/` 直接出 PNG

## 电脑端批量解密

```bash
python pc_unpack.py --rbt <Assets.rbt> --log <pwd.txt> --out <输出目录>
```

自动从 log 里抓全部 `pwd=[...]`，逐层拆包直到真实文件。
