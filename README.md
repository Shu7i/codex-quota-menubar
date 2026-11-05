# Codex 额度菜单显示小工具

一个 macOS 菜单栏小工具，用来显示 Codex 的 5 小时额度和周额度。

## 此分支的定制功能

- 胶囊内显示距离重置的倒计时，如 `2h55m`、`35min`、`3Day`；右侧仍显示剩余额度百分比。
- 支持横向／纵向排列，以及连续字号滑块。最小字号 7，横向上限为菜单栏高度，纵向上限为其一半。
- 标签颜色与百分比颜色可分别配置，支持预设颜色与系统自定义色板。
- 开启低额度预警后，可分别配置时／周剩余额度阈值与预警颜色；切换开关时菜单保持打开。
- 刷新间隔可选 30 秒、1、2、5、10、15 分钟。倒计时沿用额度查询周期，没有独立的分钟轮询。
- 支持通过菜单“开机自启”管理 macOS 登录项；开启或关闭均由系统登录项机制处理，无额外常驻进程。
- 设置保存在应用自己的 UserDefaults 中，兼容旧设置；支持查找 ChatGPT 应用内部附带的 Codex CLI。

本 fork 保留原项目作者与 MIT 许可。

由嘉文钱开发并开源。工程内部名称保留为 `CodexQuotaBar`，方便 SwiftPM、脚本和路径保持稳定。

<img width="2500" height="3333" alt="幻灯片12" src="https://github.com/user-attachments/assets/17b1d78e-0c44-4e8b-a82f-177e8e5ee2dd" />

## 适合用在

- 想在 macOS 顶部菜单栏里一直看到 Codex 剩余额度。
- 想快速确认 5 小时窗口和周额度窗口的刷新时间。
- 想在额度低于或等于 20% 时有一个明显提醒。
- 自己日常使用 Codex，希望少打开一个页面或少进一次 Codex 面板。

## 功能

- 菜单栏胶囊显示时／周重置倒计时，旁边显示各自剩余额度百分比。
- 菜单里显示 5 小时额度和周额度的刷新时间，精确到分钟。
- 可开启低额度提醒：默认剩余额度低于或等于 20% 时预警，可分别调整时／周阈值与颜色。
- 按配置间隔自动读取额度（默认 5 分钟），打开菜单时也会读取一次，保留手动刷新。
- 点击菜单里的「刷新」时检测一次当前壁纸颜色，深色菜单栏下自动切换为浅色显示。
- 不直接读取 `auth.json`、cookie、浏览器 session 或账号敏感文件。

## 重要说明

这个仓库推荐以源码方式分享，不默认发布预构建的 `.app` 或 `.dmg` 安装包。

原因是 macOS Gatekeeper 会拦截未经过 Apple Developer ID 签名和 notarization 公证的第三方二进制文件。别人直接下载未公证的安装包时，系统可能提示“无法打开”或识别为风险软件。

推荐使用方式是：下载源码后，在自己的 Mac 上本地构建成自用 app。

## 环境要求

- macOS 13 或更新版本。
- 已安装并登录 Codex Desktop。
- Codex Desktop 可通过 bundle id `com.openai.codex` 找到，或者本机存在：
  - `/opt/homebrew/bin/codex`
  - `/usr/local/bin/codex`

工具通过 Codex 本地 app-server 协议读取额度：

- `account/rateLimits/read`
- `account/usage/read`

## 从源码运行

```bash
git clone <this-repo-url>
cd codex-quota-menubar
./script/build_and_run.sh
```

这会在本机编译并启动菜单栏 app。

## 构建自用 DMG

```bash
./script/package_dmg.sh
```

生成文件：

```text
dist/CodexQuotaBar-0.1.4.dmg
```

注意：这个脚本默认使用 ad-hoc 签名，只适合本机自用或开发测试。不要把这个未公证的 DMG 当成正式安装包分发给其他人。

## 图标

App 图标源文件和 `.icns` 文件在：

```text
Assets/
```

## 已知限制

- Codex 的本地 app-server 协议不是公开稳定 API，未来 Codex 更新后可能需要适配。
- 默认打包脚本不会做 Apple Developer ID 签名和 notarization。
- 如果 Codex 安装在非标准位置，并且 Launch Services 找不到，需要调整 `CodexAppServerClient.swift` 里的 `codexExecutableURL()`。

## 开源协议

MIT License。

Copyright (c) 2026 Kevin Chin / 嘉文钱

## 本地验证

运行 `bash script/check_countdown.sh` 验证倒计时边界；运行 `swift build -c release` 检查编译。测试使用合成时间，不读取登录信息或请求额度接口。
