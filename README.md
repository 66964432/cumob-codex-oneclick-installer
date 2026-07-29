# codex 一键接入自定义路由 - cumob 篇

macOS / Windows 双击安装，自动完成：

1. 安装最新 `cumob-image-generation4codex` Skill
2. 写入当前 codex 一键接入自定义路由 - cumob 篇 provider 配置
3. 安装自定义模型目录 `cumob-models.json`
4. 将 CUMOB API Key 合并进 Codex `auth.json`

设计目标：

- 用户只需要下载很小的安装入口，双击即可
- 安装时从 GitHub 实时拉取最新 Skill、配置模板、模型目录
- 不打包真实 API Key
- 重复安装可升级，不破坏用户已有的其他 Codex 配置

## 仓库

- 安装器：[`66964432/cumob-codex-oneclick-installer`](https://github.com/66964432/cumob-codex-oneclick-installer)
- Skill：[`66964432/cumob-image-generation4codex`](https://github.com/66964432/cumob-image-generation4codex)

## 用户安装方式

### 方式 A：双击安装（推荐）

1. 下载本仓库最新 Release 中的：
   - `install-macos.command`
   - 或 `install-windows.cmd`
2. 双击运行
3. 输入 CUMOB API Key（输入不显示）
4. 重启 Codex，或新建一个任务

即使只下载这两个入口文件，安装器也会从 GitHub 拉取：

- 最新安装逻辑
- 最新模型目录
- 最新配置模板
- 最新 Skill

### 方式 B：直接克隆本仓库后安装

```bash
git clone https://github.com/66964432/cumob-codex-oneclick-installer.git
cd cumob-codex-oneclick-installer
bash install.sh
```

Windows PowerShell：

```powershell
git clone https://github.com/66964432/cumob-codex-oneclick-installer.git
cd cumob-codex-oneclick-installer
.\install.ps1
```

## 安装位置

优先使用 `CODEX_HOME`。未设置时：

- macOS：`~/.codex`
- Windows：`%USERPROFILE%\.codex`

写入内容：

```text
<CODEX_HOME>/
├── auth.json
├── config.toml
├── model-catalogs/
│   └── cumob-models.json
├── skills/
│   └── cumob-image-generation4codex/
└── backups/
    └── cumob-installer-YYYYMMDD-HHMMSS/
```

## 配置策略

安装器不会整文件覆盖 `config.toml`。它会：

- 先备份旧配置、旧 auth、旧模型目录、旧 Skill
- 删除旧的 CUMOB provider 段和本安装器受管段
- 写入可移植 CUMOB 配置，并生成当前机器上的模型目录绝对路径
- 保留其他 provider / MCP / 插件 / 桌面设置 / 项目权限
- 重复运行时升级，不产生重复 TOML 键

受管配置默认值：

```toml
model_provider = "cumob"
model = "gpt-5.6-sol"
disable_response_storage = true
model_reasoning_effort = "high"

[model_providers.cumob]
name = "cumob"
wire_api = "responses"
image_api = "images"
image_model = "gpt-image-2-ref"
requires_openai_auth = true
base_url = "https://api.cumob.com/v1"
```

## 安全

- 发行包与仓库都不包含真实 API Key
- API Key 不作为命令行参数传递，也不会写入安装日志
- 新 Key 只写入 `auth.json` 的 `OPENAI_API_KEY`
- 现有其他 auth 字段会保留
- 不输入 Key 时，保留已有 `auth.json`

非交互安装：

```bash
CUMOB_INSTALL_API_KEY="your-key" bash install.sh --no-prompt
```

```powershell
$env:CUMOB_INSTALL_API_KEY = "your-key"
.\install.ps1 -NoPrompt
Remove-Item Env:CUMOB_INSTALL_API_KEY
```

## 高级选项

只预览，不改文件：

```bash
bash install.sh --dry-run
```

```powershell
.\install.ps1 -DryRun
```

自定义 Codex 目录：

```bash
CODEX_HOME="/custom/path" bash install.sh
```

```powershell
$env:CODEX_HOME = "D:\CodexHome"
.\install.ps1
```

自定义远程源：

```bash
export CUMOB_INSTALLER_URL="https://github.com/66964432/cumob-codex-oneclick-installer/archive/refs/heads/main.zip"
export CUMOB_SKILL_URL="https://github.com/66964432/cumob-image-generation4codex/archive/refs/heads/main.zip"
export CUMOB_MODELS_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/payload/cumob-models.json"
bash install.sh
```

## 运行要求

- Codex 已安装
- 网络可访问 GitHub
- 图片 Skill 运行时至少有一种：
  - Node.js 18+
  - Python 3

## 开发与验证

macOS/Linux：

```bash
bash tests/test-install.sh
```

Windows：

```powershell
.\tests\test-install.ps1
```

真实联网验证（会从 GitHub 下载 Skill）：

```bash
CUMOB_LIVE_TEST=1 bash tests/test-install.sh
```

构建本地发布包：

```bash
bash build-release.sh
```

## 仓库维护建议

建议把这个目录作为独立 GitHub 仓库维护：

```text
cumob-codex-oneclick-installer/
├── install-macos.command
├── install-windows.cmd
├── install.sh
├── install.ps1
├── payload/
│   ├── cumob-config.template.toml
│   └── cumob-models.json
├── scripts/
├── tests/
├── README.md
└── SOURCE.json
```

用户日常只需要下载入口文件，配置内容全部在 GitHub 上持续更新。
