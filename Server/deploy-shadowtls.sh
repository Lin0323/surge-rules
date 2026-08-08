#!/usr/bin/env bash
# 部署 Shadowsocks 2022 + ShadowTLS v3。不会覆盖 x-ui、Caddy 或已有端口。
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_env SERVER_NAME
require_env PORT
require_env HANDSHAKE_SERVER
validate_host_and_port
[[ "$HANDSHAKE_SERVER" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "HANDSHAKE_SERVER 必须是域名或 IP。" >&2; exit 1; }
assert_port_free tcp
ensure_sing_box

SS_LOCAL_PORT="${SS_LOCAL_PORT:-$((PORT + 10000))}"
[[ "$SS_LOCAL_PORT" =~ ^[0-9]{1,5}$ ]] && (( SS_LOCAL_PORT > 0 && SS_LOCAL_PORT < 65536 )) || { echo "SS_LOCAL_PORT 不合法。" >&2; exit 1; }
PUBLIC_PORT="$PORT"
PORT="$SS_LOCAL_PORT"
assert_port_free tcp
PORT="$PUBLIC_PORT"
SS_PASSWORD="${SS_PASSWORD:-$(random_b64 32)}"
SHADOWTLS_PASSWORD="${SHADOWTLS_PASSWORD:-$(random_b64 32)}"
CONFIG_DIR="/etc/surge-nodes"
CONFIG_PATH="$CONFIG_DIR/shadowtls.json"
install -d -m 0700 "$CONFIG_DIR"

cat >"$CONFIG_PATH" <<EOF
{
  "log": {"level": "warn"},
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss2022-local",
      "listen": "127.0.0.1",
      "listen_port": $SS_LOCAL_PORT,
      "network": "tcp",
      "method": "2022-blake3-aes-256-gcm",
      "password": "$SS_PASSWORD"
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-v3",
      "listen": "::",
      "listen_port": $PORT,
      "version": 3,
      "password": "$SHADOWTLS_PASSWORD",
      "handshake": {"server": "$HANDSHAKE_SERVER", "server_port": 443},
      "detour": "ss2022-local"
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"}
}
EOF
chmod 0600 "$CONFIG_PATH"
sing-box check -c "$CONFIG_PATH"
write_secret_env shadowtls \
  "SERVER_NAME=$SERVER_NAME" "PORT=$PORT" "SS_PASSWORD=$SS_PASSWORD" \
  "SHADOWTLS_PASSWORD=$SHADOWTLS_PASSWORD" "HANDSHAKE_SERVER=$HANDSHAKE_SERVER"
install_sing_box_service shadowtls "$CONFIG_PATH"
open_ufw_port_if_requested tcp
bash "$SCRIPT_DIR/../Subscription/generate-surge-subscription.sh"
echo "部署完成。凭据已写入 $NODE_ROOT/shadowtls.env；未在终端输出。私有订阅已在 VPS 本地重新生成。"
