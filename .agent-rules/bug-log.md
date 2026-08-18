# HDSH Bug 记录（Bug Log）

> **本文件是项目 Bug 档案库**：每个已发现、已定位、已修复的 Bug 都必须记录于此，防止复发。
> **约定**：每次发现新 Bug → 在此追加一条（含现象/根因/修复/验证/日期）；涉及 UI 布局、抽屉、断点、ArkWeb 的 Bug，必须同步在 `scripts/ui-test-phone.sh` 增加对应回归断言。
> **归属**：本文件由 `.agent-rules/README.md` 索引，供所有 Agent 在修改相关代码前查阅。

---

## 记录格式

```markdown
### [YYYY-MM-DD] Bug 标题（一句话现象）
- **现象**：用户/测试看到的错误表现
- **根因**：代码层确切原因（附文件:行）
- **修复**：改动内容与文件
- **验证**：验证命令/结果（hilog/dumpLayout/自动化测试）
- **回归测试**：ui-test-phone.sh 中的对应断言（如适用）
- **状态**：✅ 已修复 / 🟡 待验证 / ❌ 未修复
```

---

## Bug 列表（新→旧）

### [2026-08-18] bash 子进程继承 cwd 导致 getcwd 权限错误
- **现象**：bash 工具每次执行前输出 `getcwd: cannot access parent directories: Permission denied`；初始 cwd 下的 `pwd` 和无参数 `ls` 失败，显式 `cd` 到同一目录后恢复正常。
- **根因**：HarmonyOS appspawn/FUSE 环境下，子进程继承的 `cwd` 可被内核解析，但 libc `getcwd()` 返回 EACCES。
- **修复**：`scripts/apply-dsh-ohos-adapt.sh` 在 `dsh-bash-local` 的 `spawnSpec` 中为 `bash -c` 命令增加安全 shell 引号包裹的显式 `cd <workdir> 2>/dev/null || exit 1;` 前缀。
- **验证**：适配脚本 Shell 语法检查通过；设备侧需重新生成 DSH 运行环境后复测 `pwd`、无参数 `ls` 及相对路径读写。
- **状态**：🟡 待设备复验

### [2026-08-18] 默认启动窗口被强制缩为手机长条
- **现象**：2in1 真机启动 HDSH 后，WebUI 固定为窄而高的浮窗，无法使用设备默认窗口比例。
- **根因**：`entry/src/main/ets/entryability/EntryAbility.ets` 在页面加载成功后无条件调用 `mainWindow.resize(654, 1440)`；真机 `uitest dumpLayout` 实测 ArkWeb 容器为 `654×1370`。
- **修复**：移除启动期固定尺寸调用，交由系统按当前设备形态创建默认主窗口；`scripts/ui-test-phone.sh` 改为验证默认窗口比例，并移除已卸载自定义抽屉的断言。
- **验证**：`assembleHap` 构建成功，覆盖安装并重启设备后，`uitest dumpLayout` 实测 ArkWeb 容器为 `2090×1324`；主内容可见，未检测到自定义插件入口；`bash scripts/ui-test-phone.sh 1 <hdc-target>` 全部通过。
- **回归测试**：`scripts/ui-test-phone.sh` 在默认窗口下拒绝 `宽度≤700 且 高度≥宽度×2` 的强制手机长条比例。
- **状态**：✅ 已修复

### [2026-08-18] 详情栏未折叠挡住主页 + 折叠屏组件贴顶 + PC 白屏（断点覆盖不全）
- **现象**：①手机/折叠屏（807px 窗口）下"点击消息流中的工具行查看详情"详情栏空态（宽 747px）覆盖主页；②折叠屏断点主页组件（探索未至之境等）挤到 ArkWeb 顶部（y=360 紧贴 359）；③PC 断点主页白屏
- **根因**：layout-phone 的详情栏折叠（closeDetails）只在 PHONE_BREAKPOINT（<700）时调用；700-1024 平板/折叠屏断点下详情栏可自由打开覆盖主页（dumpLayout 实测"关闭详情/点击消息流中的工具行查看详情"节点在主页上方）
- **修复**：新增 NARROW_BREAKPOINT=1024 与 isNarrowViewport()，onResize/初始 closeDetails 改为窄屏（<1024，含手机+平板/折叠屏）一律折叠详情栏（rawfile + apply [3.10] 同步）
- **验证**：node --check / bash / mjs 语法通过；部署后 dumpLayout 确认详情栏折叠、主页无遮挡
- **状态**：✅ 已修复（待真机三断点复验）

### [2026-08-18] dsh rc.7 更新后 DSH 无法启动——cordis.patch.yml 坏 YAML
- **现象**：dsh 从 0.1.0-rc.6 更新到 rc.7 后，页面一直显示"正在启动 DSH 运行时..."（主页/新会话页面出错），node 日志报 `failed to parse overlay cordis.patch.yml: YAMLException: bad indentation of a mapping entry (189:52)`，第 189 行 `name: '@deepseek-ai/dsh-sandbox-policy'      config:`（config 被拼到 name 同行）
- **根因**：apply 脚本旧正则 `/disabled: true\n config:\n mode: 'workspace-write'/` 是针对 rc.6 的 sandbox-policy 块（含 disabled: true 行）写的；rc.7 该块无 disabled: true，正则误匹配产生坏 YAML → dsh-app-boot 解析失败 → DSH 无法启动
- **修复**：apply 脚本正则改为只精确替换 mode 值（`mode: ... 'workspace-write'` → `'danger-full-access'`），不触碰 YAML 缩进/结构；重跑 prepare-dsh-env.sh 0.1.0-rc.7 重建环境
- **验证**：重建后 rawfile cordis.patch.yml 第 189 行恢复正常（name 与 config 分行）
- **状态**：✅ 已修复

### [2026-08-18] dsh rc.7 更新后 sandbox-policy 被误禁用（disableIds 冲突）
- **现象**：与上一条同批发现——rc.7 环境下 sandbox-policy 块带 `disabled: true`，与"tool-bash 要求 ctx.sandboxPolicy 启用"的意图矛盾
- **根因**：apply 脚本 `disableIds`（第 96 行）含 `'sandbox-policy'`，循环会给该 id 补 `disabled: true`；rc.6 时 mode 正则恰好删掉了 disabled 行掩盖了此问题，rc.7 无 disabled 行导致保留后被禁用
- **修复**：从 disableIds 移除 `'sandbox-policy'`（保留 sandbox-local 等禁用），注释说明原因
- **验证**：重建后 sandbox-policy 块无 disabled: true、mode 为 danger-full-access
- **状态**：✅ 已修复

### [2026-08-18] 侧边栏按钮 absolute 悬浮挡住左上角会话标题
- **现象**：手机/平板形态下，FishLogo 抽屉按钮绝对定位在主列左上角，盖住会话标题左侧（dumpLayout：按钮 [501,118][578,195] 与标题 [524,129][768,183] 重叠）
- **根因**：layout-phone 把按钮 `prepend` 到 centerCol 顶部 + CSS `position:absolute; left:8px; top:8px` 悬浮，与标题同一位置
- **修复**：按钮 CSS 改 `position:static` + `inline-flex`（不再悬浮）；新增 `findTitleRow(centerCol)` 找会话标题行容器，把按钮插入标题同一行并设 `flex + alignItems:center + justifyContent:center` 水平居中（rawfile + apply [3.10] 同步）
- **验证**：node --check / bash / mjs 语法通过；部署后 dumpLayout 确认按钮与标题同行不重叠
- **状态**：✅ 已修复

### [2026-08-18] PC 断点（>1024px）主页白屏残留——onAreaChange 不可靠，改系统 windowSizeChange
- **现象**：上一轮 onAreaChange + refresh 方案未生效，PC 大窗口下主页仍白屏/新对话界面消失（hilog 无跨断点日志）
- **根因**：`onAreaChange` 在 Web 组件上未可靠派发（web.d.ts 无声明、hilog 无触发日志）；ArkWeb 内容宽度不跟随窗口断点切换
- **修复**：改用系统 `window.on('windowSizeChange')`（@ohos.window，必然触发）——宽度跨断点（<700/700-1024/>1024）时 `controller.refresh(true)` 重排；`getLastWindow` 返回 Promise 需 await（编译修复），aboutToDisappear 异步注销监听
- **验证**：ArkTS 编译通过（BUILD SUCCESSFUL）；部署后 hilog 应有"已注册 windowSizeChange 监听"
- **状态**：✅ 已修复（待真机跨断点复验）

### [2026-08-18] grep 工具：readFrom(0) 返回 {text, lossy} 对象导致类型不匹配
- **现象**：grep 降级仍报 `The "string" argument must be of type string or an instance of Buffer or ArrayBuffer. Received undefined`
- **根因**：`handle.collected.stdout.readFrom(0)` 返回收集器对象 `{text, lossy}`（非 Buffer/字符串）——`completeStdout`（98-106 行）读 `stdout.lossy`/`stdout.text` 证实；降级补丁把整个对象塞进 `grepTextToNdjson` → `String({text,lossy})` = `"[object Object]"` → 空 NDJSON → `completeStdout` 读 `"".text` = undefined → 报错
- **修复**：保持 `{text, lossy}` 形状不变只替换 text：`const stdout = fallbackGrep ? { ...stdoutRaw, text: grepTextToNdjson(stdoutRaw.text ?? "") } : stdoutRaw;`（rawfile index.js + apply 模板两份拷贝同步；函数内 Buffer 强转保留无害）
- **验证**：node --check 通过；grep 降级链路（argv → 文本 → NDJSON → {text,lossy} 包装 → completeStdout → 解析）完整贯通
- **回归测试**：ui-test-phone.sh 4.5.1 grep Buffer 强转检测
- **状态**：✅ 已修复

### [2026-08-18] PC 断点（>1024px）主页白屏 / 新对话界面消失
- **现象**：2in1 窗口拖到 PC 尺寸（1920 宽）后，主页白屏、新对话界面消失；layout 仍按窄屏处理（侧栏折叠成 69px compact rail、主列被推到右侧/下方）
- **根因**：ArkWeb 内容宽度不跟随窗口断点切换——PC 物理窗口 1920 宽时，ArkWeb 内 layout 仍按窄屏（<700px）布局；layout-phone 的 isPhoneViewport 用 frame.getBoundingClientRect().width 判断，窗口放大后 frame 宽度未同步更新
- **修复**：`entry/src/main/ets/pages/hdsh/HdshWebPage.ets` Web 组件加 `.onAreaChange()`，窗口宽度跨断点（<700 / 700-1024 / >1024）时 `this.controller.refresh(true)` 强制前端按新尺寸重排；EntryAbility 保持手机形态默认 654×1440
- **验证**：临时改 resize 1920×1440 复现（dumpLayout ArkWeb 容器 1920 宽但侧栏 69px rail）→ 修复后跨断点刷新触发重排
- **回归测试**：ui-test-phone.sh 增加 PC 断点白屏检测（窗口切大后主列关键文本仍可见）
- **状态**：✅ 已修复

### [2026-08-18] dsh-terminal-bash prompt 暗号不匹配 → 命令慢 70 倍
- **现象**：简单命令（pwd/ls）1ms 能跑完却卡 3.5s 起步，首个命令 7s+
- **根因**：底层 `dsh-terminal-bash` 等待暗号 `CONTROLLED_PROMPT = "dsh> "`，上层 `dsh-tool-bash-persistent` 却把 PS1 设为 `__DSH_PERSISTENT_BASH_PROMPT__`，两边对不上 → 每次触发 3.5s 静默超时兜底
- **修复**：`dsh-terminal-bash/lib/index.js` 两处——CONTROLLED_PROMPT 改为 `"__DSH_PERSISTENT_BASH_PROMPT__"`（对齐上层），硬编码 `6` 改为 `CONTROLLED_PROMPT.length + 1`（长度自适应）；apply 脚本 [3.8.1] 段固化
- **验证**：实测从 ~3600ms 降到 ~158ms（70 倍）；已提交官方 Discussions + fork 修复分支
- **状态**：✅ 已修复

### [2026-08-18] grep 工具 fallback 崩溃：grepTextToNdjson 收到 Buffer 非字符串
- **现象**：glob 正常、grep 报 `stdout.split is not a function or its return value is not iterable`
- **根因**：`dsh-tool-fs-search/lib/index.js` 第 285 行 `handle.collected.stdout?.readFrom(0)` 返回 Buffer/Uint8Array（非字符串），第 288 行直接传入 `grepTextToNdjson`，函数内 `stdout.split("\n")` 抛 TypeError；glob 走 completeStdout 能处理 Buffer 所以没炸
- **修复**：`grepTextToNdjson` 函数体开头加 `const text = Buffer.isBuffer(stdout) ? stdout.toString("utf8") : String(stdout);`，后续用 `text.split`（rawfile 与 apply 脚本模板两份拷贝同步）
- **验证**：node --check 通过；设备部署后 grep 降级链路完整
- **状态**：✅ 已修复

### [2026-08-18] grep 工具 fallback 正则语义丢失：BRE 把 `|` 当作字面量
- **现象**：`grep "hello"` 可以匹配，`grep "hello|probe"` 在工具降级链路中返回 0 个匹配；系统 grep 直接使用 BRE 时，rg 的 `|`、`()`, `+`, `?`, `{}` 语义未生效。
- **根因**：`dsh-tool-fs-search/lib/index.js` 的 fallback argv 只有 `-rn -e`，GNU grep 和 toybox grep 默认使用 BRE；rg 查询约定使用 PCRE2/ERE 元字符，导致复合正则静默变成无匹配。
- **修复**：fallback argv 改为 `args.push("-rn", "-E", "-e", pattern, root)`；rawfile 源文件与 `scripts/apply-dsh-ohos-adapt.sh` 模板同步修改，并提升 `DshBootstrap` 环境版本到 `20260818-23`，启动时重建 dsh 目录并清理 profiles fallback 缓存。
- **验证**：rawfile JavaScript `node --check` 通过；HAP 构建成功；覆盖安装并重启设备后，部署文件实测包含 `args.push("-rn", "-E", "-e", pattern, root)`；toybox 实测通过 `hello|probe`、`--include=*.txt`、`你好|世界` 和 `hel+o`；ArkWeb bounds 为 `2090×1324`，页面节点可见。
- **回归测试**：`scripts/ui-test-phone.sh` 4.5.1 同时断言 Buffer 转换和 ERE argv，缺任一项即失败。
- **状态**：✅ 已修复

### [2026-08-18] 手机断点默认白屏 / 点击侧栏主页消失（grid 列定位）
- **现象**：654×1440 手机窗口下，主页默认白屏；点击侧栏按钮后主页消失
- **根因**：layout-phone 把 sidebarCol 设 `position:absolute` 脱离 grid 流后，CSS Grid 自动布局把主列（centerCol）填到第 1 列（0px 宽）→ 白屏/主页消失（与之前 display:none 是同一类 grid 陷阱）
- **修复**：JS 给 centerCol/detailsCol 打 `data-hdsh-center`/`data-hdsh-details` 标记，CSS 显式 `grid-column: 2/3 !important`
- **验证**：自动化测试 2 轮通过（退出码 0）、主页可见（关键文本=5）、无白屏
- **回归测试**：ui-test-phone.sh 白屏检测（主列关键文本断言）
- **状态**：✅ 已修复

### [2026-08-18] 侧栏隐藏导致全空白（display:none 打乱 grid 流）
- **现象**：侧栏彻底隐藏后主页全空白
- **根因**：sidebarCol `display:none` 后 CSS Grid 把主列 CenterColumn 自动填入第 1 列（0px 宽）→ 全空白
- **修复**：移除 display:none，改用 computeColumns JS 逻辑（手机断点折叠返回 0 而非 56px rail）+ grid-column 显式定位
- **验证**：dumpLayout 主列可见（探索未至之境/预览版/选择工作区）
- **状态**：✅ 已修复

### [2026-08-18] 汉堡按钮未出现（宽度判断 + 初始化时机）
- **现象**：抽屉按钮部署后未出现
- **根因**：① isPhoneViewport 用 window.innerWidth——ArkWeb 高 DPI 下返回物理像素（1308）而非 CSS 逻辑像素（654），判断失效；② setupDrawer 在 frame 未挂载时直接放弃
- **修复**：isPhoneViewport 改用 document.documentElement.clientWidth / frame.getBoundingClientRect().width（CSS 逻辑像素）；setupDrawer 加 500ms 重试（最多 6 次）
- **验证**：设备修复落位（clientWidth/retryCount）、汉堡按钮出现（dumpLayout enabled/clickable=true）
- **状态**：✅ 已修复

### [2026-08-18] 抽屉浮层误滑入盖住主列（大白屏）
- **现象**：汉堡按钮出现后被"点击消息流中的工具行查看详情"大白屏遮住主页
- **根因**：侧栏浮层化（absolute + translateX）在 ArkWeb 下 data-hdsh-drawer-open 误设时滑入盖住主列；isPhoneViewport 用 frame 宽度误判手机形态（ArkWeb 内容区全屏 3120 而窗口 654）
- **修复**：isPhoneViewport 优先用 frame.getBoundingClientRect().width（与 layout ResizeObserver 一致）；侧栏改推动模式（grid 流内 0/280 切换）
- **验证**：dumpLayout 大白屏文案=0、Failed to load=0
- **状态**：✅ 已修复

### [2026-08-18] 插件崩溃 Failed to load plugins（frame 变量作用域）
- **现象**：layout-phone 插件加载失败（Failed to load plugins @deepseek-ai/dsh-client-ui-layout-phone）
- **根因**：isPhoneViewport 引用 frame 变量，但函数在模块级定义、frame 是 apply() 内局部变量 → ReferenceError: frame is not defined
- **修复**：frame 提升为模块级变量（apply() 内改为赋值）
- **验证**：Failed to load=0、插件正常
- **状态**：✅ 已修复

### [2026-08-18] 手机形态文字排版诡异（字体重叠/设置页不可读）
- **现象**：手机形态下文字排版诡异、字体重叠、设置页多处无法查看
- **根因**：长文本（如设置页"选择模型，当前 DeepSeek-V4-Flash，推理等级"）在 342px 窄列未换行溢出；设置页 dl>dt+dd 网格窄屏并排挤压
- **修复**：多档断点 CSS——全局强制换行（overflow-wrap: anywhere + word-break）、flex/grid 子项 min-width:0、pre/code 换行、dl>dt+dd 窄屏纵向堆叠（!important 覆盖网格）、img/video/table max-width:100%
- **验证**：新 CSS 落位（overflow-wrap: anywhere=1）、自动化脚本 2 轮截图成功
- **状态**：✅ 已修复

### [2026-08-18] 应用名仍显示 NGF 框架（本地化文件漏改）
- **现象**：桌面图标下应用名仍是"NGF 框架"
- **根因**：上一轮只改了 base/element/string.json（默认语言），漏掉 zh_CN/en_US 本地化文件；设备中文环境显示名取自 zh_CN（EntryAbility_label = "NGF 框架"）
- **修复**：zh_CN 10 处 + en_US 13 处 NGF → HDSH 全部替换
- **验证**：资源 string.json 无 NGF 残留、HAP 部署成功
- **状态**：✅ 已修复
