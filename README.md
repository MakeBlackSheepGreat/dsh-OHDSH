# HDSH

HDSH 是面向 HarmonyOS Next 的 DSH 运行环境实现。项目以 `entry` 承载应用层与设备适配，以 `ngf_framework` 提供可复用的原生基础设施。

## 当前状态

当前应用已经可以在 HarmonyOS 设备上启动 DSH 官方 WebUI：`EntryAbility` 加载 `pages/hdsh/HdshWebPage`，应用在沙箱中准备 DSH、busybox 和 pnpm 运行环境，启动本地 DSH 服务后由 ArkWeb 加载 `http://127.0.0.1:3080`。

已验证的当前交付结果：

- 包名：`com.hdsh.agentic`
- 目标与兼容 SDK：HarmonyOS `6.1.0(23)`
- 支持声明：phone、tablet、2in1、car、tv、wearable
- 设备回归：主页可见、默认窗口比例正常、PC 断点不白屏
- 文件搜索 fallback：在 ripgrep 不可用时使用系统 grep，并保持 ERE 正则语义
- 公开仓库不包含签名材料、凭据或本机环境文件

当前版本重点是 DSH WebUI 运行闭环与设备适配。ArkTS 原生 harness、设置、工具和 MCP 能力仍按 [迁移方案](docs/migration-plan.md) 继续演进。

## 目录

```text
HDSH/
├── entry/                 # HDSH 应用层、入口 Ability、ArkWeb 页面和运行时桥接
├── ngf_framework/         # 可复用 HarmonyOS 基础框架
├── scripts/               # DSH 环境准备、二进制准备和真机回归脚本
├── docs/                  # 架构、迁移、构建和变更记录
├── .rules/                # 通用 Agent 工程规则
├── .agent-rules/          # HDSH 项目规则与 Bug 档案
└── AGENTS.md              # 工作区协作规范
```

`entry/src/main/resources/rawfile/dsh/`、`busybox/`、`pnpm/` 和 native 运行时文件由准备脚本生成或下载，默认不提交到 Git。这样可以避免把大型二进制、签名材料和机器环境带入公开仓库。

## 开发环境

1. 使用 DevEco Studio 打开仓库。
2. 准备运行时文件：

```bash
bash scripts/prepare-dsh-env.sh 0.1.0-rc.7
bash scripts/fetch-busybox.sh
bash scripts/fetch-pnpm.sh
HDSH_LIBNODE_URL=<approved-libnode-url> bash scripts/fetch-libnode.sh
```

3. 在本地 DevEco Studio 签名设置中配置开发签名，签名文件只保存在本机。
4. 使用 Hvigor 构建 `entry` 模块并安装到设备。
5. 执行真机回归：

```bash
bash scripts/ui-test-phone.sh 1 <hdc-target>
```

脚本要求显式传入设备 target，避免把具体设备标识写入项目。

## 文档

- [迁移方案](docs/migration-plan.md)
- [busybox 运行环境](docs/dsh-busybox-linux-env.md)
- [NGF 框架现状](docs/NGF_FRAMEWORK_STATUS.md)
- [变更日志](docs/CHANGELOG.md)
- [Agent 协作规范](AGENTS.md)

## 许可证

MIT，见 [LICENSE](LICENSE)。
