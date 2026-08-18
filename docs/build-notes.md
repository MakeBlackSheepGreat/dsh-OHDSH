# HDSH 构建说明

本文档描述公开仓库的通用构建流程，不记录具体用户路径、设备标识、签名材料或凭据。

## 环境前置

- 安装与 `build-profile.json5` 中 `targetSdkVersion` 兼容的 DevEco Studio/HarmonyOS SDK。
- 安装项目声明的 Node.js、npm 和 Hvigor 依赖。
- 将 `DEVECO_SDK_HOME` 设置为当前机器的 SDK 根目录。
- 需要设备测试时，将 `hdc` 加入 `PATH`，或设置 `HDSH_HDC` 为 `hdc` 可执行文件路径。

## 构建命令

```bash
export DEVECO_SDK_HOME=<harmonyos-sdk-root>
npm ci
# 使用 DevEco Studio 配套的 hvigor.js
node <devtools-hvigor-root>/bin/hvigor.js assembleHap --no-daemon
```

Windows PowerShell 可使用：

```powershell
$env:DEVECO_SDK_HOME = '<harmonyos-sdk-root>'
node '<devtools-hvigor-root>/bin/hvigor.js' assembleHap --no-daemon
```

签名配置只在本地 DevEco Studio 或本机安全存储中提供，证书、私钥和密码禁止提交到仓库。

## DSH 运行环境准备

- `scripts/prepare-dsh-env.sh`：npm 安装 DSH → rawfile/dsh（gitignore）
- `scripts/fetch-libnode.sh`：下载 libnode.so → entry/libs/arm64-v8a/
- `scripts/fetch-busybox.sh`：下载 busybox → rawfile/busybox/
- `scripts/apply-dsh-ohos-adapt.sh`：对 DSH 环境应用 OpenHarmony 适配
