# codex 一键接入自定义路由 - cumob 篇

适用系统：macOS / Windows  
适用对象：最终用户

## 安装前准备

1. 已安装 [Codex](https://chatgpt.com/codex)
2. 电脑可访问 GitHub
3. 准备好你的 CUMOB API Key

## 一键安装（推荐）

### macOS

1. 下载：[`install-macos.command`](https://github.com/66964432/cumob-codex-oneclick-installer/releases/latest/download/install-macos.command)
2. 双击运行
3. 如果系统提示“无法打开”，请：
   - 右键文件 → 选择“打开”
   - 或到“系统设置 → 隐私与安全性”中允许运行
4. 按提示输入 CUMOB API Key  
   - 输入时不会显示字符，属正常现象
   - 如果本机已配置过 Key，可直接回车跳过
5. 看到 `Installation finished` 后，关闭窗口
6. 重启 Codex，或新建一个任务

### Windows

1. 下载：[`install-windows.cmd`](https://github.com/66964432/cumob-codex-oneclick-installer/releases/latest/download/install-windows.cmd)
2. 双击运行
3. 如果 SmartScreen 拦截，选择“仍要运行”
4. 按提示输入 CUMOB API Key  
   - 输入时不会显示字符，属正常现象
   - 如果本机已配置过 Key，可直接回车跳过
5. 看到 `Installation finished` 后，按任意键关闭窗口
6. 重启 Codex，或新建一个任务

## 安装后会自动完成什么

安装器会自动从 GitHub 拉取并配置：

- 最新 `cumob-image-generation4codex` Skill
- CUMOB 模型目录
- CUMOB provider 配置
- API Key 到 Codex `auth.json`

默认写入位置：

- macOS：`~/.codex`
- Windows：`%USERPROFILE%\.codex`

## 如何确认安装成功

打开 Codex 后检查：

1. 模型列表里能看到 CUMOB 模型，例如 `gpt-5.6-sol`
2. 可以调用图片 Skill：`cumob-image-generation4codex`
3. 生成图片时不再提示缺少 API Key / provider

## 升级

以后如果 Skill 或配置有更新：

1. 再次双击同一个安装入口
2. 安装器会重新拉取最新版本并覆盖升级
3. 你的其他 Codex 配置会保留
4. 旧文件会自动备份

## 常见问题

### 1. 安装失败，提示网络错误

请确认：

- 能打开 GitHub
- 没有被公司代理/防火墙拦截
- 可访问：
  - `https://github.com/66964432/cumob-codex-oneclick-installer`
  - `https://github.com/66964432/cumob-image-generation4codex`

然后重新双击安装。

### 2. 安装成功，但 Codex 里看不到变化

请：

1. 完全退出 Codex 再打开
2. 或新建一个任务
3. 再检查模型列表和 Skill

### 3. API Key 输错了怎么办

再次运行安装入口，重新输入正确 Key 即可。

### 4. 会不会覆盖我原来的 Codex 配置？

不会整份覆盖。安装器只会：

- 更新 CUMOB 相关配置
- 保留其他 provider / 插件 / 桌面设置
- 先备份旧文件

备份目录：

- macOS：`~/.codex/backups/`
- Windows：`%USERPROFILE%\.codex\backups\`

## 下载入口

- 安装器仓库：https://github.com/66964432/cumob-codex-oneclick-installer
- Skill 仓库：https://github.com/66964432/cumob-image-generation4codex
- 最新发布页：https://github.com/66964432/cumob-codex-oneclick-installer/releases/latest

如果你只想最快完成安装，记住这 4 步：

**下载入口 → 双击安装 → 输入 API Key → 重启 Codex**
