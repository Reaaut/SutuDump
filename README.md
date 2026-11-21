# SutuDump v2

寰俊涓婚鍖咃紙`.rbt` / `Assets.rbt`锛夊瘑鐮佹姄鍙?+ 鑷姩瑙ｅ寘銆?
## 涓ょ鐢ㄦ硶

### A. Frida锛堥浂缂栬瘧锛岀珛鍒荤敤锛?
```bash
frida -U -f <AppBundleID> -l frida_sutu.js --no-pause
```

鎴栧凡杩愯锛?
```bash
frida -U -n <杩涚▼鍚? -l frida_sutu.js
```

鎵撳紑涓婚鍟嗗簵椤?/ 瀵煎叆涓婚锛屾棩蹇楅噷鍑虹幇锛?
```
[SUTU] PWD xxxxxxxx  (ZZOld)
[SUTU] unpacked 1551 entries -> /var/mobile/Documents/sutu_dump/out/xxxxxx
```

浜х墿锛?
```
/var/mobile/Documents/sutu_dump/
鈹溾攢 pwd.txt             涓€琛屼竴涓瘑鐮侊紙鍘婚噸锛?瀵嗙爜>\t<鏉ユ簮>锛?鈹溾攢 raw/                鎶撳埌鐨勫灞?rbt
鈹斺攢 out/<pwd鍓?浣?/     鑷姩鎷嗗ソ鐨?PNG锛堝灞?鍐呭眰閫掑綊鎷嗗畬锛?```

### B. 缂栬瘧鎴?dylib锛堣 .dylib / .deb 鐢ㄨ繖涓級

鏈満娌℃湁 macOS 宸ュ叿閾撅紝鐢?GitHub Actions 鑷姩缂栵細

1. 鏂板缓浠撳簱锛屾妸鏈洰褰曪紙鍚?`.github/`锛塸ush 涓婂幓
2. Actions 鑷姩璺?`macos-14` runner锛岃 Theos + iOS SDK
3. 璺戝畬鍦?Artifacts 閲屼笅 `SutuDump-build`锛?   - `*.deb`锛坮ootless 鐗堬級
   - `*_SutuDump.dylib`锛堝彲鐩存帴涓㈣繘 MobileSubstrate 鐩綍锛?
鏈湴 Mac 缂栬瘧锛?
```bash
export THEOS=~/theos
make clean
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

瀹夎锛?
```bash
scp packages/*.deb root@device:/var/root/
ssh root@device "dpkg -i /var/root/*.deb && killall -9 SpringBoard"
```

## 娉ㄥ叆鐩爣

`SutuDump.plist` 閲岀殑 `Bundles` 瑕佸～浣犺澶囦笂閭ｄ釜 App 鐨?bundle id锛?
```
Filza 鈫?/var/containers/Bundle/Application/<UUID>/xxx.app/Info.plist 鈫?CFBundleIdentifier
```

涓嶇煡閬撶殑璇濆厛濉?`com.apple.springboard` 娴嬪姞杞斤紝鍐嶆崲鎴愮湡瀹?id銆?
## hook 鐐?
| 绫?/ 鏂规硶 | 浣滅敤 |
|---|---|
| `ZZOldArchiveEntry -newDataWithPassword:error:` | 涓诲瘑鐮佹潵婧愶紙澶栧眰 rbt锛?|
| `ZZNewArchiveEntry -newDataWithPassword:error:` | 鏂版牸寮忔潯鐩?|
| `ZZStandardDecryptInputStream -initWithStream:password:header:check:version:error:` | ZipCrypto 搴曞眰瀵嗙爜 + check |
| `NSJSONSerialization +JSONObjectWithData:options:error:` | 浠庢帴鍙ｅ搷搴旈噷鐩存帴鎹炲瘑鐮侊紙涓嶇敤涓嬭浇涓婚锛?|
| `NSUserDefaults -objectForKey:` (`ThemeCurentAssetFloderNameKey`) | 璁板綍涓婚缂撳瓨鐪熷疄璺緞锛屾柟渚垮鍖呰Е鍙?|

## 鏂规 4锛氫笉涓嬭浇涔熻兘瑙﹀彂

1. 鎵撳紑 App 杩涗竴娆′富棰橀〉 鈫?`theme_folder.txt` 閲屽嚭鐜扮湡瀹炵紦瀛樿矾寰?2. 鎶婂埆浜哄彂浣犵殑 `.rbt` 鏀瑰悕 `Assets.rbt`锛屽杩涜涓婚鐩綍
3. 鍥?App 鐐硅繖涓富棰樼殑**棰勮**锛堜笉鐐瑰簲鐢級
4. `pwd.txt` 澶氫竴琛岋紝`out/` 鐩存帴鍑?PNG

鍏ㄧ▼涓嶄笅杞姐€佷笉搴旂敤涓婚銆?
## 宸茬煡鍐呭眰瀵嗙爜

鎵€鏈変富棰樼殑鍐呭眰璧勬簮瀵嗙爜缁熶竴涓猴細

```
2E@Qws#b9MQ6p4^sRS
```

澶栧眰瀵嗙爜鎸夌郴鍒椾笅鍙戯紙鍚岀郴鍒楀叡鐢ㄤ竴涓級锛岀洰鍓嶅凡鎶撳埌锛?
```
^or$.^WLkaUs6crfVEkg!Q!EbO0d2eXi1Hsn_YbSK^8z7pWIz4I   鈫?Gossip 绯诲垪
zfnl7nfiyC$WLQGbF8NDgPrQCudgRcipuFOZOzXpZgunWGm4oU!   鈫?Paste 绯诲垪
```

