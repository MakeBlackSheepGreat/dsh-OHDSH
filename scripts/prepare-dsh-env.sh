#!/bin/bash
# ============================================================
# HDSH: 准备 DSH 运行环境（rawfile/dsh）
# 将 @deepseek-ai/dsh 及其依赖完整安装到临时目录，应用 OpenHarmony 适配，
# 再拷入 entry/src/main/resources/rawfile/dsh/ 随 HAP 分发。
#
# 用法: scripts/prepare-dsh-env.sh [dsh版本，默认 0.1.0-rc.7]
# 产物: entry/src/main/resources/rawfile/dsh/（gitignore 不提交，需重新构建 HAP）
# 注意: 原生模块（node-pty/sharp/koffi）在鸿蒙无预编译 binding，
#       安装后由 apply-dsh-ohos-adapt.sh stub；若 Windows 编译失败可加 --ignore-scripts。
# ============================================================
set -e
DSH_VERSION="${1:-0.1.0-rc.7}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="entry/src/main/resources/rawfile/dsh"

if [ -f "$DEST/.hdsh-env-ready" ]; then
  echo "DSH 环境已就绪: $DEST"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "[1/4] 创建临时工程并安装 dsh@$DSH_VERSION (node_modules 较大，请耐心等待)..."
cd "$TMP"
npm init -y >/dev/null 2>&1
# 原生模块在 Windows 编译失败属预期：--ignore-scripts 跳过 postinstall，
# 需要的模块由 adapt 脚本 stub（dsh 核心为纯 JS，可正常运行）。
npm install --no-audit --no-fund --ignore-scripts "@deepseek-ai/dsh@$DSH_VERSION"

echo "[2/4] 校验 dsh 主入口..."
[ -f node_modules/@deepseek-ai/dsh/lib/bin.js ] || { echo "错误: bin.js 不存在"; exit 1; }

# HDSH 鸿蒙适配：预装 typescript（run_code 类型剥离用）。必须在此处用 bash
# 的 tar 解压——apply-dsh-ohos-adapt.sh 内 Node execSync('tar') 在 Windows
# cmd PATH 找不到 Git Bash 的 tar（status 2）；这里预装后 apply 检查
# node_modules/typescript/lib/typescript.js 存在即跳过。
echo "[2.5/4] 预装 typescript（run_code 类型剥离）..."
mkdir -p node_modules/typescript
npm pack typescript@5.9.3 --pack-destination node_modules/typescript >/dev/null 2>&1
TS_TGZ="$(ls node_modules/typescript/typescript-*.tgz 2>/dev/null | head -1)"
if [ -n "$TS_TGZ" ]; then
  tar -xzf "$TS_TGZ" -C node_modules/typescript --strip-components=1
  rm -f "$TS_TGZ"
  echo "typescript 预装完成: $(ls node_modules/typescript/lib/typescript.js 2>/dev/null)"
else
  echo "警告: typescript 预装失败（npm pack 无产物），apply 阶段将尝试兜底"
fi

# HDSH 鸿蒙适配：预装 pnpm（dsh plugin 主进程桥接用）。同样用 bash tar
# 解压，避免 apply 脚本内 Node execSync('tar') 在 Windows cmd PATH 找不到。
echo "[2.6/4] 预装 pnpm（dsh plugin 主进程桥接）..."
mkdir -p node_modules/pnpm
npm pack pnpm@10.6.3 --pack-destination node_modules/pnpm >/dev/null 2>&1
PNPM_TGZ="$(ls node_modules/pnpm/pnpm-*.tgz 2>/dev/null | head -1)"
if [ -n "$PNPM_TGZ" ]; then
  tar -xzf "$PNPM_TGZ" -C node_modules/pnpm --strip-components=1
  rm -f "$PNPM_TGZ"
  echo "pnpm 预装完成: $(ls node_modules/pnpm/dist/pnpm.cjs 2>/dev/null)"
else
  echo "警告: pnpm 预装失败（npm pack 无产物），apply 阶段将尝试兜底"
fi

echo "[3/4] 应用 OpenHarmony 适配（stub 原生模块 + bundle patch）..."
bash "$SCRIPT_DIR/apply-dsh-ohos-adapt.sh" "$TMP"

echo "[4/4] 拷入 rawfile/dsh..."
rm -rf "$REPO_ROOT/$DEST"
mkdir -p "$REPO_ROOT/$DEST"
cp -r node_modules "$REPO_ROOT/$DEST/node_modules"
touch "$REPO_ROOT/$DEST/.hdsh-env-ready"

echo "✅ DSH 环境就绪: $REPO_ROOT/$DEST ($(du -sh "$REPO_ROOT/$DEST" | cut -f1))"
echo "   请重新构建 HAP（rawfile/dsh 会随包分发，首次启动由 DshBootstrap 解压到沙箱）"
