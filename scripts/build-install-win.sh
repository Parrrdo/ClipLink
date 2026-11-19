#!/usr/bin/env bash
# Windows(Git Bash) 下一键：编译 -> 签名 -> 安装到手机 -> 启动
# 用法: ./scripts/build-install-win.sh            # 自动挑设备（优先无线）
#       ./scripts/build-install-win.sh -clean     # 先清干净再构建
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE="com.xiebaiyuan.syncclipboard.harmony"
ABILITY="EntryAbility"
HAP_DIR="entry/build/default/outputs/default"
HAP="entry-default-signed.hap"

DEVECO_HOME="${DEVECO_HOME:-D:/DevEco Studio}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/sdk}"
export NODE_HOME="${NODE_HOME:-$DEVECO_HOME/tools/node}"
HVIGORW="$DEVECO_HOME/tools/hvigor/bin/hvigorw.js"
HDC="$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc.exe"

[ -x "$HDC" ] || { echo "找不到 hdc: $HDC"; exit 1; }

# 0) 还原签名配置（build-profile.local.json5 -> build-profile.json5）
node scripts/prepare-build-profile.cjs

# 1) 可选 clean
if [ "${1:-}" = "-clean" ]; then
  node "$HVIGORW" clean --no-daemon || true
fi

# 2) 构建 + 签名
node "$HVIGORW" assembleHap --mode module -p product=default -p buildMode=debug --no-daemon

[ -f "$HAP_DIR/$HAP" ] || { echo "没有生成 $HAP —— 检查 .sign/sign-config.json5 与 build-profile.local.json5 里的签名配置"; exit 1; }

# 3) 选设备：优先无线调试（ip:port），其次 USB
DEVICE="$("$HDC" list targets 2>/dev/null | tr -d '\r' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+$' | head -1 || true)"
if [ -z "$DEVICE" ]; then
  DEVICE="$("$HDC" list targets 2>/dev/null | tr -d '\r' | grep -vE '^(COM|$)' | head -1 || true)"
fi
[ -n "$DEVICE" ] || { echo "没有可用设备：手机需开 USB 调试或无线调试，并 hdc tconn <ip>:<port>"; exit 1; }
echo ">> 使用设备: $DEVICE"

# 4) 覆盖安装（-r 保留数据）
( cd "$HAP_DIR" && "$HDC" -t "$DEVICE" install -r "$HAP" )

# 5) 拉起（锁屏时系统拒绝自动启动，属正常，解锁后手动点图标即可）
"$HDC" -t "$DEVICE" shell "aa start -a $ABILITY -b $BUNDLE" \
  || echo ">> 安装已成功，但设备锁屏无法自动拉起，解锁后手动打开应用"
echo ">> 完成"
