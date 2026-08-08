# 节点管理层

这里定义 Surge 可用节点的模板和生成规则，不保存任何真实凭据。

## 协议优先级

1. Shadowsocks 2022 + ShadowTLS v3：主力 TCP 节点。
2. AnyTLS：TLS 备用节点，要求 Surge iOS 5.17 或以上。
3. Hysteria2：UDP/QUIC 备用节点，要求 Surge iOS 5.8 或以上。
4. Snell v5：Surge 专用备用节点。
5. VLESS Reality：保持原有服务与配置不变；Surge iOS 没有 VLESS 策略类型，因此不会写入 Surge 订阅。

## 使用方式

在 VPS 上依次运行 Server/ 中的部署脚本。脚本会在 VPS 的 /etc/surge-nodes/ 下生成仅 root 可读的本地凭据文件，再由 Subscription/generate-surge-subscription.sh 生成包含 Surge Proxy 和 Proxy Group 的私有订阅文件。

生成出的订阅文件绝不能提交到 GitHub、聊天记录或公开网页。通过你自己的 HTTPS 私有入口发布时，必须配置访问控制。
