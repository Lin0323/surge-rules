#!/usr/bin/env bash
# 部署 Hysteria2 UDP/QUIC 备用节点；需先为 SERVER_NAME 准备有效 TLS 证书。
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_env SERVER_NAME
require_env PORT
validate_host_and_port
assert_port_free udp
require_tls_files
ensure_sing_box

HYSTERIA2_PASSWORD="${HYSTERIA2_PASSWORD:-$(random_b64 32)}"
UP_MBPS="${UP_MBPS:-100}"
DOWN_MBPS="${DOWN_MBPS:-100}"
[[ "$UP_MBPS" =~ ^[0-9]+$ && "$DOWN_MBPS" =~ ^[0-9]+$ ]] || { echo "UP_MBPS 与 DOWN_MBPS 必须是整数。" >&2; exit 1; }
CONFIG_DIR="/etc/surge-nodes"
CONFIG_PATH="$CONFIG_DIR/hysteria2.json"
install -d -m 0700 "$CONFIG_DIR"

cat >"$CONFIG_PATH" <<EOF
{
  "log": {"level": "warn"},
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "::",
      "listen_port": $PORT,
      "up_mbps": $UP_MBPS,
      "down_mbps": $DOWN_MBPS,
      "users": [{"name": "surge", "password": "$HYSTERIA2_PASSWORD"}],
      "tls": {"enabled": true, "certificate_path": "$CERT_PATH", "key_path": "$KEY_PATH"},
      "masquerade": {"type": "string", "status_code": 404, "content": "Not Found"}
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"}
}
EOF
chmod 0600 "$CONFIG_PATH"
sing-box check -c "$CONFIG_PATH"
write_secret_env hysteria2 \
  "SERVER_NAME=$SERVER_NAME" "PORT=$PORT" "HYSTERIA2_PASSWORD=$HYSTERIA2_PASSWORD"
install_sing_box_service hysteria2 "$CONFIG_PATH"
open_ufw_port_if_requested udp
bash "$SCRIPT_DIR/../Subscription/generate-surge-subscription.sh"
echo "部署完成。凭据已写入 $NODE_ROOT/hysteria2.env；未在终端输出。私有订阅已在 VPS 本地重新生成。"
