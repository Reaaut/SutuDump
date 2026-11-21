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
├─ pwd.txt             一行一个密码（去重，<密码>\t<来源>）
├─ raw/                抓到的外层 rbt
└─ out/<pwd前6位>/     自动拆好的 PNG（外层+内层递归拆完）
```

### B. 编译成 dylib（要 .dylib / .deb 用这个）

本机没有 macOS 工具链，用 GitHub Actions 自动编：

1. 新建仓库，把本目录（含 `.github/`）push 上去
2. Actions 自动跑 `macos-14` runner，装 Theos + iOS SDK
3. 跑完在 Artifacts 里下 `SutuDump-build`：
   - `*.deb`（rootless 版）
   - `*_SutuDump.dylib`（可直接丢进 MobileSubstrate 目录）

本地 Mac 编译：

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

## 注入目标

`SutuDump.plist` 里的 `Bundles` 要填你设备上那个 App 的 bundle id：

```
Filza → /var/containers/Bundle/Application/<UUID>/xxx.app/Info.plist → CFBundleIdentifier
```

不知道的话先填 `com.apple.springboard` 测加载，再换成真实 id。

## hook 点

| 类 / 方法 | 作用 |
|---|---|
| `ZZOldArchiveEntry -newDataWithPassword:error:` | 主密码来源（外层 rbt） |
| `ZZNewArchiveEntry -newDataWithPassword:error:` | 新格式条目 |
| `ZZStandardDecryptInputStream -initWithStream:password:header:check:version:error:` | ZipCrypto 底层密码 + check |
| `NSJSONSerialization +JSONObjectWithData:options:error:` | 从接口响应里直接捞密码（不用下载主题） |
| `NSUserDefaults -objectForKey:` (`ThemeCurentAssetFloderNameKey`) | 记录主题缓存真实路径，方便塞包触发 |

## 方案 4：不下载也能触发

1. 打开 App 进一次主题页 → `theme_folder.txt` 里出现真实缓存路径
2. 把别人发你的 `.rbt` 改名 `Assets.rbt`，塞进该主题目录
3. 回 App 点这个主题的**预览**（不点应用）
4. `pwd.txt` 多一行，`out/` 直接出 PNG

全程不下载、不应用主题。

## 已知内层密码

所有主题的内层资源密码统一为：

```
2E@Qws#b9MQ6p4^sRS
```

外层密码按系列下发（同系列共用一个），目前已抓到：

```
^or$.^WLkaUs6crfVEkg!Q!EbO0d2eXi1Hsn_YbSK^8z7pWIz4I   → Gossip 系列
zfnl7nfiyC$WLQGbF8NDgPrQCudgRcipuFOZOzXpZgunWGm4oU!   → Paste 系列
```
