# Surge iOS 自动化配置工程

这是一个面向 Surge iOS 的公开配置工程：GitHub 只保存规则、模块、脚本和无敏感信息的入口配置。真实节点、密码、UUID、Reality 私钥、WireGuard 私钥等仅保留在你的 Surge 本机配置中。

## 目录

- Config/Main.conf：主入口配置。
- Modules/：可单独安装的功能模块。
- Rules/：轻量分类规则集。
- Scripts/：手动诊断与通知脚本。
- .github/workflows/：GitHub 自动校验。

旧版 Surge/ 目录暂时保留，仅为不影响已经使用旧链接的配置；新配置请从 Config/Main.conf 与 Modules/ 开始。

## 安装

1. 在 iPhone Safari 打开 Main.conf 的 Raw 链接：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Config/Main.conf>，选择“在 Surge 中打开”。它是无敏感信息的托管入口，默认每天检查一次更新。
2. 在 Surge 的配置编辑器中，将自己的节点添加到 [Proxy]；或从你可信的订阅导入节点后，记录节点名称。不要将这些信息提交到 GitHub。
3. 在 [Proxy Group] 中把节点名称加进 Proxy。例如：Proxy = select, 我的 Trojan, 我的 Hysteria2, DIRECT；Backup = fallback, 我的 Trojan, 我的 Hysteria2, DIRECT, url=https://cp.cloudflare.com/generate_204, interval=600, timeout=8。
4. 策略组含义：Proxy 是默认海外流量；AI 处理 OpenAI/Claude/Gemini/Cursor；Media 处理流媒体；Developer 处理开发资源；Apple 可按需要指定出口；Backup 按可达性切换。

Main.conf 初始只使用 DIRECT，确保未填真实节点时仍能导入。填入节点后再按上例更新策略组即可。

## 模块

在 Surge 的“模块”页用以下直链安装。模块会覆盖主配置中的同名设置，请按需启用。

- Core：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Modules/Core.sgmodule>
- AI：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Modules/AI.sgmodule>
- Developer：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Modules/Developer.sgmodule>
- Privacy：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Modules/Privacy.sgmodule>
- NetworkTools：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Modules/NetworkTools.sgmodule>
- Debug：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Modules/Debug.sgmodule>；仅排障时安装，默认不要启用。

## 规则和 DNS

- 规则按顺序首次命中；广告/拒绝规则在前，国内和局域网直连在后，最后才是默认策略。
- 规则集保持轻量，只包含清晰、可维护的域名分类；它不是“大而全”的广告库。
- 传统 DNS 用阿里/腾讯 DNS 服务国内域名；其他请求使用 DoH/DoH3。hijack-dns 用于减少应用绕过 Surge DNS 的机会。
- Apple 推送、内网地址和常见国内金融/通讯服务都保留直连规则。若某个 App 异常，请先在 Surge 日志中确认实际命中的域名，再谨慎调整。

## 脚本

在 Surge 的“脚本”页手动运行：

- 出口 IP 检查：显示 IP、国家/城市和 ASN。
- 节点健康检查：测试 Proxy 与 Backup 策略组可达性；通用公开配置不能枚举你的私有节点。
- 网络信息：探测直连网络基础可达性并显示可读取的网络名称。
- 异常通知测试：DoH 探测失败时发出 Surge 通知。

## 维护和安全

- 修改规则、模块或脚本后，GitHub Actions 会检查空文件、重复规则、规则格式、模块元数据和 URL 有效性。
- 本地预检查：python Scripts/验证配置.py --skip-urls；完整 URL 检查：python Scripts/验证配置.py。
- 严禁上传 VPS 密码、节点密码、UUID、Reality 私钥、ShadowTLS 密码或 WireGuard 私钥。.gitignore 已忽略本地私密配置模板。
- 广告拦截无法保证覆盖所有应用内广告；过度拦截可能影响支付、登录或内容加载。
