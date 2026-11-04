#!/bin/bash
#
# KeyboardLocker 构建脚本
#
#   ./build.sh           构建 build/KeyboardLocker.app
#   ./build.sh --run     构建后直接启动
#   ./build.sh --install 构建后安装到 /Applications 并启动
#
#   KEYBOARDLOCKER_ADHOC=1 ./build.sh   强制 ad-hoc 签名（release.sh 发版用）
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeyboardLocker"
BUNDLE_ID="com.fair.keyboardlocker"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
ICNS="$BUILD_DIR/AppIcon.icns"
ICON_SOURCE="Tools/make-icon.swift"

RUN_AFTER=0
INSTALL_AFTER=0
for arg in "$@"; do
    case "$arg" in
        --run) RUN_AFTER=1 ;;
        --install) INSTALL_AFTER=1; RUN_AFTER=1 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------- 图标
if [ ! -f "$ICNS" ] || [ "$ICON_SOURCE" -nt "$ICNS" ]; then
    echo "==> 生成应用图标"
    swift "$ICON_SOURCE" "$BUILD_DIR/icon-1024.png" >/dev/null

    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"

    while read -r size name; do
        sips -z "$size" "$size" "$BUILD_DIR/icon-1024.png" --out "$ICONSET/$name.png" >/dev/null
    done <<'SPECS'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SPECS

    iconutil -c icns "$ICONSET" -o "$ICNS"
    echo "    $ICNS"
fi

# ---------------------------------------------------------------- 编译
echo "==> 编译 $APP_NAME"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

ARCH="$(uname -m)"
xcrun swiftc \
    -O -whole-module-optimization \
    -swift-version 5 \
    -target "${ARCH}-apple-macos13.0" \
    -o "$CONTENTS/MacOS/$APP_NAME" \
    Sources/*.swift

# ---------------------------------------------------------------- 组装
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp "$ICNS" "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"
xattr -cr "$APP" 2>/dev/null || true

# ---------------------------------------------------------------- 签名
# 如果本机存在自签名的开发证书，用它签名可以让 TCC 授权在重新编译后继续有效；
# 否则退回 ad-hoc 签名（每次重新编译后需要在系统设置里重新勾选权限）。
SIGN_IDENTITY="KeyboardLocker Dev"
if [ "${KEYBOARDLOCKER_ADHOC:-0}" = "1" ]; then
    echo "==> 签名（ad-hoc，发布模式）"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "==> 签名（$SIGN_IDENTITY）"
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "==> 签名（ad-hoc）"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

codesign --verify --strict "$APP"
echo "==> 完成: $APP"

# ---------------------------------------------------------------- 可选动作
if [ "$INSTALL_AFTER" -eq 1 ]; then
    echo "==> 安装到 /Applications"
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "已安装并启动 /Applications/$APP_NAME.app"
elif [ "$RUN_AFTER" -eq 1 ]; then
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    sleep 0.5
    open "$APP"
    echo "已启动 $APP"
fi
