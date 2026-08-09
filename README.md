# Surge iOS 自动化配置工程

此仓库是 Surge iOS 的公开配置层，只保存分流规则、模块、诊断脚本、节点模板和 VPS 部署脚本。真实节点、密码、UUID、私钥、订阅链接和认证令牌永不提交 GitHub。

## 目录

- Config/：主入口配置，包含 General、Proxy、Proxy Group、Rule、DNS、Script、MITM。
- Rules/：轻量分类规则集。
- Modules/：按需安装的功能模块。
- Scripts/：出口、节点与服务连通性诊断。
- Nodes/：Surge 节点格式模板及协议说明。
- Subscription/：仅在 VPS 本地生成私有 Surge 订阅。
- Server/：部署 Shadowsocks 2022 + ShadowTLS v3、AnyTLS、Hysteria2、Snell 的脚本。

旧版 Surge/ 目录保持不动，避免已在使用的旧规则链接失效。后续功能维护以根目录的新结构为准。

## GitHub 配置管理

1. 在 iPhone Safari 打开主入口 Raw 链接：<https://raw.githubusercontent.com/Lin0323/surge-rules/main/Config/Main.conf>，选择“在 Surge 中打开”。
2. 此入口不包含任何节点。首次导入后 Auto 只有 DIRECT，是为了保证配置可以安全导入。
3. 从你的私有订阅导入节点，或仅在本机添加节点；绝不把真实 Proxy 配置回传到仓库。
4. 在策略组中把真实节点名称加入 Auto，并删除 Auto 中的 DIRECT。Auto 会通过 Cloudflare 204 测试自动选择延迟最低的可用节点。

Auto、Proxy、AI、Media、Developer、Apple、Backup 的用途如下：

- Auto：逐节点测速并自动选择。
- 外部节点：用于导入私有 Surge 外部代理列表；在 Surge 的“外部代理”入口粘贴列表 URL，节点会纳入该策略组。真实 URL 不写入 GitHub。
- Proxy：默认海外流量入口，可选择 Auto、外部节点或 DIRECT。
- AI：ChatGPT、Claude、Gemini、Cursor 等。
- Media：YouTube、Netflix、Disney+、Max、Prime Video、Twitch 等。
- Developer：GitHub、GitLab、Docker、NPM、PyPI 等。
- Apple：Apple 服务的独立出口选择。
- Spotify：Spotify 的独立出口选择，可手动选择 Proxy 或 DIRECT。
- Backup：主策略不可用时的回退策略。

## VPS 节点生成

Server/ 的脚本默认不会覆盖 x-ui、Caddy、VLESS Reality 或已有端口；端口已占用时会停止。每个脚本必须以 root 运行，并显式提供 SERVER_NAME 与 PORT。ShadowTLS 还要求提供 HANDSHAKE_SERVER。TLS 类型节点必须已有有效证书。

推荐顺序：

1. Shadowsocks 2022 + ShadowTLS v3：主力 TCP 节点。
2. AnyTLS：TLS 备用。
3. Hysteria2：UDP/QUIC 备用。
4. Snell v5：Surge 专用备用。

示例仅说明调用方式，不包含真实值：SERVER_NAME=节点域名 PORT=端口 HANDSHAKE_SERVER=公开 TLS 域名 bash Server/deploy-shadowtls.sh。若要让脚本精确开放 UFW 端口，额外设置 OPEN_FIREWALL=1；未设置时脚本不会改动防火墙。

部署脚本将服务配置与随机生成的凭据写入 VPS 的 /etc/surge-nodes/，目录权限为 0700，文件权限为 0600；凭据不会打印到终端。

## Surge 私有订阅更新

在 VPS 上以 root 运行 Subscription/generate-surge-subscription.sh。它读取 /etc/surge-nodes/ 中的本地凭据，生成 /var/lib/surge-subscription/Surge.conf，并只写入已实际部署的节点。

生成器不监听端口、不启动 Web 服务、不打印订阅内容。要启用自动更新，必须先自行部署 HTTPS 私有入口，再由 root 设置 SUBSCRIPTION_URL。私有入口应使用高熵随机路径令牌，并叠加 Caddy Basic Auth、Cloudflare Access 或 mTLS；详见 Subscription/订阅安全说明.md。

VLESS Reality 保持现有配置，不由这些脚本修改；Surge iOS 没有 VLESS 策略类型，因此不会把它写进 Surge 订阅。

## 网络诊断 Panel

`Config/Main.conf` 已内置名为“网络诊断”的动态 Panel，不需要日常进入“脚本”页。

- 显示：当前代理出口 IP/地区、最终策略或自动选路候选、Wi-Fi/Cellular、DNS 可达状态、节点连通、Google、TikTok、ChatGPT 与最后更新时间。
- 刷新：轻触 Panel 的刷新按钮即并行执行完整检测；`update-interval=600`，在进入 Surge 策略选择页时最多每 10 分钟自动刷新一次。这是 Surge Panel 的官方刷新行为，不会在后台高频请求。
- 代理路径：所有外部检测都显式指定 `Proxy` 策略组，不会因为脚本默认 DIRECT 而把本地运营商 IP 误报成代理出口。
- 通知：出口 IP、节点或 DNS 的异常会汇总为一条“核心网络”通知；关键服务连续两次检测失败才通知；恢复正常后通知一次。状态保存在 Surge 的持久化存储中，避免刷新时反复通知。
- DNS：Panel 只读取系统 DNS 状态，不发起 DoH/DoQ 探测，也不会修改 `dns-server`、DNS 劫持、IPv6 或 TikTok 分流。主配置默认不启用 `encrypted-dns-server`，避免影响现有解析。

旧的单项脚本仍保留在 `Scripts/` 供排障或二次开发参考，但不再由 Main.conf 或 `NetworkTools.sgmodule` 注入为日常手动入口。`Debug.sgmodule` 继续保留“异常通知测试”，仅在排障时启用。

官方参考：

- https://manual.nssurge.com/others/panel.html
- https://manual.nssurge.com/scripting/common.html
- https://manual.nssurge.com/others/http-api.html

## 安全与维护

- 严禁上传 VPS 密码、节点密码、UUID、Reality 私钥、ShadowTLS 密码、AnyTLS 密码、Snell PSK、WireGuard 私钥或订阅链接。
- 修改后运行 python Scripts/验证配置.py --skip-urls 做静态检查；完整 URL 检查使用 python Scripts/验证配置.py。
- GitHub Actions 还会检查规则格式、重复规则、空文件、模块元数据、URL 和 Shell 语法。
- 广告拦截不能保证覆盖所有应用内广告；异常时应先查看 Surge 日志，再谨慎调整规则。
