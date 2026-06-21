#!/bin/bash
# 重新编译「蓝牙麦克风守护」
# 改完 源码/main.swift 后,双击本文件即可重新生成 app。

cd "$(dirname "$0")" || exit 1
APP="Lyssen.app"

echo "正在编译……"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "源码/Info.plist" "$APP/Contents/Info.plist"
cp "源码/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

swiftc 源码/main.swift \
    -o "$APP/Contents/MacOS/Lyssen" \
    -framework AppKit -framework SwiftUI -framework CoreAudio -framework ServiceManagement \
    -O

if [ $? -ne 0 ]; then
    echo "❌ 编译失败,请把上面的报错发给我。"
    read -n1 -p "按任意键关闭……"
    exit 1
fi

# 本地 ad-hoc 签名,减少 Gatekeeper 拦截
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "✅ 编译完成!双击「$APP」即可启动。"
read -n1 -p "按任意键关闭……"
