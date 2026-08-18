#!/bin/bash
# ============================================================
# HDSH 默认窗口 UI 自动化测试脚本（2in1 真机）
#
# 用途：验证系统默认窗口尺寸下 DSH 官方 WebUI 是否正确——
#   - 白屏检测：主列内容必须可见（探索未至之境/预览版/工作区等）
#   - 比例检测：ArkWeb 容器不得回退到 654×1440 的强制手机长条
#   - 使用 dsh 官方侧栏与布局，不断言已移除的自定义抽屉
#   - 截图留档供人工/视觉检查
#
# 用法：
#   scripts/ui-test-phone.sh [次数] [target]
#     次数  循环轮数（默认 1）
#     target hdc 目标（必须显式传入，或设置 HDSH_HDC_TARGET）
#
# 依赖：hdc、uitest（设备端 UI 测试框架）、python
# ============================================================
set -u
ROUNDS="${1:-1}"
TARGET="${2:-${HDSH_HDC_TARGET:-}}"
if [ -z "$TARGET" ]; then
  echo "[ui-test-phone] FAIL: 必须显式传入 hdc target 或设置 HDSH_HDC_TARGET"
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 可通过 HDSH_HDC 指定 hdc；否则从 PATH 查找，避免绑定到某台机器的 SDK 路径。
HDC="${HDSH_HDC:-}"
if [ -z "$HDC" ]; then
  HDC="$(command -v hdc 2>/dev/null || true)"
fi
if [ -z "$HDC" ]; then
  echo "[ui-test-phone] FAIL: 未找到 hdc，请设置 HDSH_HDC 或将 hdc 加入 PATH"
  exit 1
fi
if command -v cygpath >/dev/null 2>&1; then
  OUT_WIN="$(cygpath -w "$ROOT")/build/ui-test-phone"
elif command -v wslpath >/dev/null 2>&1; then
  OUT_WIN="$(wslpath -w "$ROOT")/build/ui-test-phone"
else
  OUT_WIN="$ROOT/build/ui-test-phone"
fi
if command -v python >/dev/null 2>&1; then
  PYTHON="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "[ui-test-phone] FAIL: 未找到 Python 解释器"
  exit 1
fi
mkdir -p "$OUT_WIN"
OUT="$ROOT/build/ui-test-phone"

# --- 工具函数 ---
# dumpLayout 并拉回，返回 JSON 路径（失败返回空）
dump_layout() {
  local tag="$1"
  local remote="/data/local/tmp/hdsh_${tag}.json"
  local local_f="$OUT/layout_${tag}.json"
  timeout 20 "$HDC" -t "$TARGET" shell "uitest dumpLayout -p $remote" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 timeout 15 "$HDC" -t "$TARGET" file recv "$remote" "$OUT_WIN/layout_${tag}.json" >/dev/null 2>&1
  if [ -f "$local_f" ]; then
    echo "$local_f"
  else
    echo ""
  fi
}

# 分析布局：返回 JSON（文本数/白屏/侧栏按钮/侧栏状态）
analyze_layout() {
  local f="$1"
  "$PYTHON" - "$f" <<'PYEOF'
import json, sys, re
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(0)
def walk(n, out=None):
    out = out or []
    if isinstance(n, dict):
        out.append(n)
        for c in n.get('children', []):
            walk(c, out)
    return out
nodes = walk(d)
texts = []
main_bounds = []
for n in nodes:
    a = n.get('attributes', n)
    t = str(a.get('text', a.get('content-desc', a.get('description', '')))).strip()
    if t and len(t) > 1:
        texts.append(t)
    # 主列关键文本的 bounds（用于抽屉右移断言）
    if any(k in t for k in ('探索未至之境', '预览版', '选择工作区', '标准模式')):
        nums = re.findall(r'\d+', str(a.get('bounds', '')))
        if len(nums) == 4:
            main_bounds.append([int(x) for x in nums])
# 主列可见性关键文本（手机断点主页应包含）
KEY_MAIN = ('探索未至之境', '预览版', '选择工作区', '标准模式', '命令', '新建会话')
main_hit = [t for t in texts if any(k in t for k in KEY_MAIN)]
# 侧栏按钮（抽屉开合）
open_btn = [t for t in texts if t in ('打开侧边栏',)]
collapse_btn = [t for t in texts if t in ('收起侧边栏',)]
# 侧栏内容（展开时可见；收起态侧栏在 grid 0px 列被裁剪，dumpLayout 通常不显示）
side_hit = [t for t in texts if t in ('新建会话', '工作区', '搜索会话', '添加工作区')]
# ArkWeb 内容容器 bounds（窗口尺寸验证）
ark_bounds = ''
for n in nodes:
    a = n.get('attributes', n)
    if '127.0.0.1:3080' in str(a.get('text', '')):
        ark_bounds = str(a.get('bounds', ''))
        break
print(json.dumps({
    "total": len(nodes),
    "texts": len(texts),
    "main_hit": main_hit[:4],
    "main_count": len(main_hit),
    "open_btn": open_btn[:2],
    "collapse_btn": collapse_btn[:2],
    "side_hit": side_hit[:4],
    "side_count": len(side_hit),
    "main_bounds": main_bounds[:4],
    "ark_bounds": ark_bounds,
}))
PYEOF
}

# 从布局 JSON 文件提取数值（直接读文件，避免 echo 管道转义/解析问题）
val_from_layout() {
  local f="$1" key="$2"
  "$PYTHON" - "$f" "$key" <<'PYEOF'
import json, sys, re
key = sys.argv[2]
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    print(0)
    sys.exit(0)
def walk(n, out=None):
    out = out or []
    if isinstance(n, dict):
        out.append(n)
        for c in n.get('children', []):
            walk(c, out)
    return out
nodes = walk(d)
texts = []
main_bounds = []
for n in nodes:
    a = n.get('attributes', n)
    t = str(a.get('text', a.get('content-desc', a.get('description', '')))).strip()
    if t and len(t) > 1:
        texts.append(t)
    if any(k in t for k in ('探索未至之境', '预览版', '选择工作区', '标准模式')):
        nums = re.findall(r'\d+', str(a.get('bounds', '')))
        if len(nums) == 4:
            main_bounds.append([int(x) for x in nums])
KEY_MAIN = ('探索未至之境', '预览版', '选择工作区', '标准模式', '命令', '新建会话')
main_hit = [t for t in texts if any(k in t for k in KEY_MAIN)]
open_btn = [t for t in texts if t in ('打开侧边栏',)]
side_hit = [t for t in texts if t in ('新建会话', '工作区', '搜索会话', '添加工作区')]
vals = {
    "main_count": len(main_hit),
    "open_btn": len(open_btn),
    "side_count": len(side_hit),
    "main_x": main_bounds[0][0] if main_bounds else 0,
}
print(vals.get(key, 0))
PYEOF
}

# 提取 ArkWeb 容器尺寸；页面未就绪或节点不存在时输出 0 0。
web_size() {
  local f="$1"
  "$PYTHON" - "$f" <<'PYEOF'
import json, re, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    print('0 0')
    sys.exit(0)
def walk(n):
    if isinstance(n, dict):
        yield n
        for c in n.get('children', []):
            yield from walk(c)
for n in walk(d):
    a = n.get('attributes', n)
    if '127.0.0.1:3080' in str(a.get('text', '')):
        nums = [int(x) for x in re.findall(r'\d+', str(a.get('bounds', '')))]
        if len(nums) == 4:
            print(str(nums[2] - nums[0]) + ' ' + str(nums[3] - nums[1]))
            sys.exit(0)
print('0 0')
PYEOF
}

# 从布局 JSON 提取"打开侧边栏"按钮中心坐标（用于精确点击）
btn_center() {
  local f="$1"
  "$PYTHON" - "$f" <<'PYEOF'
import json, sys, re
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    print("")
    sys.exit(0)
def walk(n, out=None):
    out = out or []
    if isinstance(n, dict):
        out.append(n)
        for c in n.get('children', []):
            walk(c, out)
    return out
for n in walk(d):
    a = n.get('attributes', n)
    t = str(a.get('text', a.get('content-desc', a.get('description', '')))).strip()
    if t == '打开侧边栏':
        nums = re.findall(r'\d+', str(a.get('bounds', '')))
        if len(nums) == 4:
            x = (int(nums[0]) + int(nums[2])) // 2
            y = (int(nums[1]) + int(nums[3])) // 2
            print(f"{x} {y}")
            break
else:
    print("")
PYEOF
}

# --- 1) 启动应用 ---
echo "[ui-test-phone] 启动应用..."
timeout 15 "$HDC" -t "$TARGET" shell hilog -r >/dev/null 2>&1
timeout 15 "$HDC" -t "$TARGET" shell aa force-stop com.hdsh.agentic 2>/dev/null
timeout 15 "$HDC" -t "$TARGET" shell aa start -a EntryAbility -b com.hdsh.agentic -m entry 2>&1 | tail -1

# --- 2) 等待 DSH server 就绪 ---
echo "[ui-test-phone] 等待 DSH server 就绪..."
READY=0
for i in $(seq 1 40); do
  if timeout 10 "$HDC" -t "$TARGET" shell "hilog -D 1 --tail=500 2>/dev/null | grep -q 'DSH server 就绪'" 2>/dev/null; then
    READY=1
    break
  fi
  sleep 3
done
if [ "$READY" != "1" ]; then
  echo "[ui-test-phone] FAIL: DSH server 未在 120s 内就绪"
  exit 1
fi
echo "[ui-test-phone] DSH server 就绪"

# --- 3) 等待页面渲染稳定（ArkWeb 加载）---
sleep 15

# --- 4) 每轮：截图 + 白屏检测 + 默认比例检测 ---
PASS_ALL=1
for round in $(seq 1 "$ROUNDS"); do
  echo "[ui-test-phone] === 第 $round/$ROUNDS 轮 ==="
  TS="$(date +%H%M%S)"
  ROUND_OK=1

  # 4.1 截图
  timeout 20 "$HDC" -t "$TARGET" shell "uitest screenCap -p /data/local/tmp/hdsh_ui_${TS}.png" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 timeout 15 "$HDC" -t "$TARGET" file recv "//data/local/tmp/hdsh_ui_${TS}.png" "$OUT_WIN/ui_${TS}.png" >/dev/null 2>&1
  if [ -f "$OUT/ui_${TS}.png" ]; then
    echo "[ui-test-phone] 截图: $OUT/ui_${TS}.png"
  else
    echo "[ui-test-phone] WARN: 截图拉取失败"
  fi

  # 4.2 白屏检测
  J1="$(dump_layout "s${TS}")"
  if [ -z "$J1" ]; then
    echo "[ui-test-phone] WARN: dumpLayout 拉取失败"
    ROUND_OK=0
  else
    R1="$(analyze_layout "$J1")"
    echo "[ui-test-phone] 页面分析: $R1"
    # 白屏判断：主列关键文本 < 1 → FAIL（直接读文件，避开 echo 管道）
    MAIN1="$(val_from_layout "$J1" main_count)"
    if [ "${MAIN1:-0}" -lt 1 ]; then
      echo "[ui-test-phone] FAIL: 主页白屏（主列关键文本 = $MAIN1）"
      ROUND_OK=0
    else
      echo "[ui-test-phone] PASS: 主页可见（关键文本 = $MAIN1）"
    fi
    # 654×1440 是旧入口 resize 的唯一目标；2in1 默认窗口不应回退到该长条比例。
    WEB_SIZE="$(web_size "$J1")"
    WEB_WIDTH="${WEB_SIZE%% *}"
    WEB_HEIGHT="${WEB_SIZE##* }"
    if [ "${WEB_WIDTH:-0}" -le 700 ] && [ "${WEB_HEIGHT:-0}" -ge $((WEB_WIDTH * 2)) ]; then
      echo "[ui-test-phone] FAIL: 默认窗口仍为强制手机长条（ArkWeb = ${WEB_WIDTH}×${WEB_HEIGHT}）"
      ROUND_OK=0
    elif [ "${WEB_WIDTH:-0}" -le 0 ] || [ "${WEB_HEIGHT:-0}" -le 0 ]; then
      echo "[ui-test-phone] FAIL: 未找到 ArkWeb 容器尺寸"
      ROUND_OK=0
    else
      echo "[ui-test-phone] PASS: 默认窗口比例正常（ArkWeb = ${WEB_WIDTH}×${WEB_HEIGHT}）"
    fi
  fi

  if [ "$ROUND_OK" != "1" ]; then PASS_ALL=0; fi
  sleep 2
done

# --- 4.5 回归检查（已修复 Bug 防复发）---
echo "[ui-test-phone] === 回归检查（Bug 防复发）==="
REGRESSION_OK=1

# 4.5.1 grep 工具链路：部署文件必须同时保留 Buffer 转换和 ERE argv
GF="$(timeout 15 "$HDC" -t "$TARGET" shell "cat /data/app/el2/100/base/com.hdsh.agentic/haps/entry/files/dsh/node_modules/@deepseek-ai/dsh-tool-fs-search/lib/index.js 2>/dev/null | grep -c 'Buffer.isBuffer(stdout)'" | tr -d '\r')" 2>/dev/null
GE="$(timeout 15 "$HDC" -t "$TARGET" shell "cat /data/app/el2/100/base/com.hdsh.agentic/haps/entry/files/dsh/node_modules/@deepseek-ai/dsh-tool-fs-search/lib/index.js 2>/dev/null | grep -F -c 'args.push(\"-rn\", \"-E\", \"-e\", pattern, root)'" | tr -d '\r')" 2>/dev/null
if [ "${GF:-0}" -ge 1 ] && [ "${GE:-0}" -ge 1 ]; then
  echo "[ui-test-phone] PASS: grep 工具 Buffer 强转与 ERE argv 已部署（grep bug 回归）"
else
  echo "[ui-test-phone] FAIL: grep 部署回归不完整（Buffer=${GF:-0}, ERE=${GE:-0}）"
  REGRESSION_OK=0
fi

# 4.5.2 dsh-terminal-bash：prompt 暗号必须为 __DSH_PERSISTENT_BASH_PROMPT__
TBF="/data/app/el2/100/base/com.hdsh.agentic/haps/entry/files/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js"
if timeout 15 "$HDC" -t "$TARGET" shell "grep -q '__DSH_PERSISTENT_BASH_PROMPT__' $TBF 2>/dev/null"; then
  echo "[ui-test-phone] PASS: terminal-bash 暗号已对齐（命令提速 bug 回归）"
else
  echo "[ui-test-phone] WARN: 未检测到暗号对齐（可能环境未重新解压）"
fi

# 4.5.3 PC 断点白屏检测：主列关键文本可见（手机/平板/PC 断点均应可见）
JPC="$(dump_layout "pc${TS}")"
if [ -n "$JPC" ]; then
  MPC="$(val_from_layout "$JPC" main_count)"
  ABC_SIZE="$(web_size "$JPC")"
  ABC="${ABC_SIZE%% *}"
  if [ "${MPC:-0}" -lt 1 ]; then
    echo "[ui-test-phone] FAIL: PC 断点白屏回归——主列不可见（关键文本 = $MPC）"
    REGRESSION_OK=0
  else
    echo "[ui-test-phone] PASS: PC 断点白屏回归——主列可见（关键文本 = $MPC，ArkWeb 宽 = ${ABC}px）"
  fi
fi

if [ "$REGRESSION_OK" != "1" ]; then PASS_ALL=0; fi

# --- 5) 汇总 ---
if [ "$PASS_ALL" = "1" ]; then
  echo "[ui-test-phone] ✅ 全部 $ROUNDS 轮通过"
  exit 0
else
  echo "[ui-test-phone] ❌ 存在失败轮次，详见上方"
  exit 1
fi
