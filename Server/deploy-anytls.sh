#!/usr/bin/env bash
# 部署 AnyTLS；需先为 SERVER_NAME 准备有效 TLS 证书。
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_env SERVER_NAME
require_env PORT
validate_host_and_port
assert_port_free tcp
require_tls_files
ensure_sing_box

ANYTLS_PASSWORD="${ANYTLS_PASSWORD:-$(random_b64 32)}"
CONFIG_DIR="/etc/surge-nodes"
CONFIG_PATH="$CONFIG_DIR/anytls.json"
install -d -m 0700 "$CONFIG_DIR"

cat >"$CONFIG_PATH" <<EOF
{
  "log": {"level": "warn"},
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [{"name": "surge", "password": "$ANYTLS_PASSWORD"}],
      "tls": {"enabled": true, "certificate_path": "$CERT_PATH", "key_path": "$KEY_PATH"}
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"}
}
EOF
chmod 0600 "$CONFIG_PATH"
sing-box check -c "$CONFIG_PATH"
write_secret_env anytls "SERVER_NAME=$SERVER_NAME" "PORT=$PORT" "ANYTLS_PASSWORD=$ANYTLS_PASSWORD"
install_sing_box_service anytls "$CONFIG_PATH"
open_ufw_port_if_requested tcp
bash "$SCRIPT_DIR/../Subscription/generate-surge-subscription.sh"
echo "部署完成。凭据已写入 $NODE_ROOT/anytls.env；未在终端输出。私有订阅已在 VPS 本地重新生成。"
