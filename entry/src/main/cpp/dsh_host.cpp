/**
 * HDSH DSH 宿主（libdsh_host.so）
 *
 * 被 ArkTS 层通过 startNativeChildProcess("libdsh_host.so:Main") 拉起：
 *   fork 子进程 → 本文件 Main() → 注入 busybox/Linux 环境 → dlopen(libnode.so) →
 *   node::Start() → 启动 DSH
 *
 * DSH 运行目录解析顺序：
 *   1. 环境变量 HDSH_DSH_DIR（若子进程继承）
 *   2. 硬编码标准沙箱路径 /data/storage/el2/base/haps/entry/files/dsh
 *      （DshBootstrap 将 DSH 运行环境解压到 context.filesDir/dsh）
 *
 * busybox 目录解析顺序（提供 dsh bash/Linux 命令环境）：
 *   1. 环境变量 HDSH_BUSYBOX_DIR
 *   2. DSH 目录同级 /data/storage/el2/base/haps/entry/files/busybox
 *      （DshBootstrap.ensureBusybox 解压 rawfile/busybox 到 context.filesDir/busybox）
 */
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <unistd.h>
#include <dirent.h>
#include <cerrno>
#include <sys/stat.h>
#include <sys/wait.h>

/** node::Start(int argc, char** argv) 符号（libnode.so 导出）。 */
typedef int (*NodeStartFn)(int argc, char** argv);

/** dlopen libnode.so 并以给定 argv 启动嵌入式 Node。返回 0 成功，负值失败。 */
static int RunEmbeddedNode(const std::vector<char*>& argv) {
    void* handle = dlopen("libnode.so", RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
        return -1;
    }
    NodeStartFn startFn = reinterpret_cast<NodeStartFn>(dlsym(handle, "_ZN4node5StartEiPPc"));
    if (startFn == nullptr) {
        return -2;
    }
    return startFn(static_cast<int>(argv.size()), const_cast<char**>(argv.data()));
}

/**
 * 注入 busybox/Linux 环境变量，供 dsh 的 bash 工具（tool-bash）使用：
 *   PATH   = <busyboxDir>:$PATH    —— 软链 sh/bash 直接可调
 *   SHELL  = <busyboxDir>/sh       —— 默认 shell（dsh 据此定位 shell）
 *   HOME   = <filesDir>/home       —— 可写家目录（dsh 会话与配置）
 *   TERM   = xterm                 —— 多数 CLI 工具需要 TERM 才不报错
 * busybox 目录不存在时静默跳过（不阻塞 DSH 启动，仅 bash 工具不可用）。
 */
static void InjectBusyboxEnv(const std::string& dshDir) {
    std::string busyboxDir;
    const char* envDir = std::getenv("HDSH_BUSYBOX_DIR");
    if (envDir != nullptr && *envDir != '\0') {
        busyboxDir = envDir;
    } else {
        // DSH 目录同级：<filesDir>/busybox
        std::string filesDir = dshDir;
        std::string::size_type pos = filesDir.rfind('/');
        if (pos != std::string::npos) {
            filesDir = filesDir.substr(0, pos);
        }
        busyboxDir = filesDir + "/busybox";
    }

    std::string busyboxBin = busyboxDir + "/busybox";
    if (access(busyboxBin.c_str(), F_OK) != 0) {
        // busybox 未解压（首次启动/解压失败）：跳过，DSH 核心功能仍可用
        return;
    }

    // ArkTS 侧 @ohos.file.fs 无 chmod API，可执行权限在此补齐（0755）。
    // 沙箱禁止 symlink，DshBootstrap 以复制方式创建 applet（sh/bash/...），
    // 复制产物同样需要可执行权限，统一对 busybox 目录内所有文件 chmod 0755。
    chmod(busyboxBin.c_str(), 0755);
    DIR* dir = opendir(busyboxDir.c_str());
    if (dir != nullptr) {
        struct dirent* entry;
        while ((entry = readdir(dir)) != nullptr) {
            std::string name = entry->d_name;
            if (name == "." || name == "..") {
                continue;
            }
            std::string appletPath = busyboxDir + "/" + name;
            chmod(appletPath.c_str(), 0755);
        }
        closedir(dir);
    }

    // PATH：hnp/系统工具优先（鸿蒙沙箱禁止 exec filesDir 下 ELF，
    // busybox 二进制不可执行；/data/service/hnp/bin 与 /system/bin 可 exec），
    // busybox 目录保留在后，最后保留原有 PATH。
    std::string path = "/data/service/hnp/bin:/system/bin:/system/xbin";
    path = path + ":" + busyboxDir;
    const char* oldPath = std::getenv("PATH");
    if (oldPath != nullptr && *oldPath != '\0') {
        path = path + ":" + oldPath;
    }
    setenv("PATH", path.c_str(), 1);
    // SHELL：hnp bash 可 exec（OH_Skills 实测：系统 /bin/sh 在沙箱域无 MAC
    // 执行权，failed to spawn shell: Permission denied os error 13；
    // /data/service/hnp/bin/bash 在 hnp_file:s0 域可 exec 且语义完整）
    setenv("SHELL", "/data/service/hnp/bin/bash", 1);
    setenv("TERM", "xterm", 1);

    // pnpm standalone（dsh plugin 前向器依赖）：<filesDir>/pnpm/pnpm
    // 沙箱无 node 可执行，内置 linuxstatic-arm64 SEA；chmod 后加入 PATH。
    std::string filesDir = dshDir;
    std::string::size_type pos = filesDir.rfind('/');
    if (pos != std::string::npos) {
        filesDir = filesDir.substr(0, pos);
    }
    std::string pnpmDir = filesDir + "/pnpm";
    std::string pnpmBin = pnpmDir + "/pnpm";
    if (access(pnpmBin.c_str(), F_OK) == 0) {
        chmod(pnpmBin.c_str(), 0755);
        path = pnpmDir + ":" + path;
        setenv("PATH", path.c_str(), 1);
    }

    // HOME：filesDir/home，可写且与 DSH 数据同区
    std::string home = filesDir + "/home";
    mkdir(home.c_str(), 0700);
    setenv("HOME", home.c_str(), 1);
}

/**
 * 启动自检：fork+execv 验证 busybox sh 与 pnpm standalone 在沙箱内可执行。
 * 输出写入 stderr（已重定向到 node-*.log），供 ArkTS dumpNodeLogs 回读确认。
 */
static void RunSelfCheck(const std::string& busyboxDir, const std::string& pnpmDir) {
    auto runCmd = [](const std::string& exe, const std::vector<std::string>& args) {
        pid_t pid = fork();
        if (pid == 0) {
            std::vector<char*> argv;
            argv.push_back(const_cast<char*>(exe.c_str()));
            for (const auto& a : args) argv.push_back(const_cast<char*>(a.c_str()));
            argv.push_back(nullptr);
            execv(exe.c_str(), argv.data());
            fprintf(stderr, "=== selfcheck exec failed: %s (%s) ===\n", exe.c_str(), strerror(errno));
            fflush(stderr);
            _exit(127);
        }
        if (pid > 0) {
            int status = 0;
            waitpid(pid, &status, 0);
            if (WIFEXITED(status)) {
                fprintf(stderr, "=== selfcheck %s exit=%d ===\n", exe.c_str(), WEXITSTATUS(status));
            } else {
                fprintf(stderr, "=== selfcheck %s signaled ===\n", exe.c_str());
            }
            fflush(stderr);
        }
    };
    std::string sh = busyboxDir + "/sh";
    runCmd(sh, {"-c", "echo BASH_SELFTEST_OK"});
    std::string pnpm = pnpmDir + "/pnpm";
    runCmd(pnpm, {"--version"});
    // 对照：系统自带二进制（沙箱是否允许 exec 系统域文件）
    runCmd("/system/bin/toybox", {"--version"});
    runCmd("/system/bin/sh", {"-c", "echo SYS_SH_OK"});
}

/** startNativeChildProcess 的子进程入口（无参，签名与鸿蒙约定一致）。 */
extern "C" __attribute__((visibility("default"))) void Main() {
    std::string dshDir;
    const char* envDir = std::getenv("HDSH_DSH_DIR");
    if (envDir != nullptr && *envDir != '\0') {
        dshDir = envDir;
    } else {
        // 标准鸿蒙应用沙箱路径：<el2 base>/haps/entry/files/dsh
        dshDir = "/data/storage/el2/base/haps/entry/files/dsh";
    }

    InjectBusyboxEnv(dshDir);

    // 鸿蒙沙箱 seccomp 过滤器禁止 io_uring（aarch64 syscall 425），
    // libuv 在 uv_loop_init 中调用 io_uring_setup 会触发 SIGSYS 崩溃。
    // 通过环境变量让 libuv 回退到 epoll 事件循环（与标准 Linux 行为一致）。
    setenv("UV_USE_IO_URING", "0", 1);

    // 鸿蒙沙箱没有 /tmp（dsh-spill-local 等插件 mkdtemp('/tmp/...') 会 ENOENT），
    // 把 TMPDIR 指到沙箱内可写目录 <filesDir>/tmp，node 的 mkdtemp 优先读 TMPDIR。
    std::string filesDirTmp = dshDir;
    std::string::size_type posTmp = filesDirTmp.rfind('/');
    if (posTmp != std::string::npos) {
        filesDirTmp = filesDirTmp.substr(0, posTmp);
    }
    std::string tmpDir = filesDirTmp + "/tmp";
    mkdir(tmpDir.c_str(), 0755);
    setenv("TMPDIR", tmpDir.c_str(), 1);
    setenv("TMP", tmpDir.c_str(), 1);
    setenv("TEMP", tmpDir.c_str(), 1);

    // 工作区根目录：dsh 的 workspaceRoot 取 process.cwd()（见 dsh-base/cordis.patch.yml），
    // 沙箱内默认 cwd 不可写会导致 workspace-write 模式全部拒绝。
    // 显式 chdir 到 <filesDir>（应用可写根），并保持与 HOME/TMPDIR 同区。
    if (chdir(filesDirTmp.c_str()) != 0) {
        fprintf(stderr, "=== libdsh_host chdir %s failed ===\n", filesDirTmp.c_str());
        fflush(stderr);
    }

    // 权限预设：bash sandboxMode 声明为 danger-full-access（HDSH 适配），
    // 须让 approval 策略同为 never，否则 permission-presets 的默认组合
    // （sandbox=danger-full-access + approval=ask）匹配不到任何预设而报错。
    setenv("DSH_PERMISSION_MODE", "danger-full-access", 1);

    // 诊断：重定向 stdout/stderr 到 <filesDir>/log/node-<pid>.log。
    // startNativeChildProcess 不提供子进程 stdio 管道，node 的报错输出无处可查；
    // 落盘后可通过 hdc 拉取 <sandbox>/files/log/node-*.log 定位退出原因。
    std::string filesDir = dshDir;
    std::string::size_type slash = filesDir.rfind('/');
    if (slash != std::string::npos) {
        filesDir = filesDir.substr(0, slash);
    }
    std::string logDir = filesDir + "/log";
    mkdir(logDir.c_str(), 0755);
    std::string logFile = logDir + "/node-" + std::to_string(getpid()) + ".log";
    freopen(logFile.c_str(), "a", stdout);
    freopen(logFile.c_str(), "a", stderr);
    fprintf(stderr, "=== libdsh_host Main() pid=%d dshDir=%s ===\n", getpid(), dshDir.c_str());
    fflush(stderr);

    // 启动自检：验证 busybox sh 与 pnpm 可 spawn（输出已重定向到本 log 文件）
    {
        std::string bbDir = filesDir + "/busybox";
        std::string pmDir = filesDir + "/pnpm";
        RunSelfCheck(bbDir, pmDir);
    }

    std::string bin = dshDir + "/node_modules/@deepseek-ai/dsh/lib/bin.js";
    // argv: node --jitless --expose-internals <dsh bin> web
    // (--expose-internals 为 HMR 插件所需)
    //
    // --jitless: HarmonyOS 沙箱 W^X 策略禁止 app 创建可执行内存（mprotect PROT_EXEC），
    //   V8 初始化时 OS::SetPermissions 触发 V8_Fatal → SIGTRAP 崩溃（见 crash:
    //   node::Start → NewIsolate → v8::Isolate::Initialize → SetPermissions）。
    //   jitless 模式不生成可执行代码，规避 execmem 需求。代价：无 JIT，纯 JS 语义不变。
    std::vector<char*> argv;
    argv.push_back(const_cast<char*>("node"));
    argv.push_back(const_cast<char*>("--jitless"));
    argv.push_back(const_cast<char*>("--expose-internals"));
    argv.push_back(const_cast<char*>(bin.c_str()));
    argv.push_back(const_cast<char*>("web"));
    RunEmbeddedNode(argv);
}
