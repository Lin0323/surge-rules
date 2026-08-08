#!/usr/bin/env bash
# 部署官方 Snell v5 服务器。此脚本不会覆盖已有端口或其它节点服务。
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_env SERVER_NAME
require_env PORT
validate_host_and_port
assert_port_free tcp
apt-get update
apt-get install -y ca-certificates curl unzip openssl

case "$(uname -m)" in
  x86_64) snell_arch="amd64" ;;
  aarch64|arm64) snell_arch="aarch64" ;;
  *) echo "不支持的 Snell 架构：$(uname -m)" >&2; exit 1 ;;
esac
SNELL_VERSION="${SNELL_VERSION:-5.0.1}"
SNELL_PSK="${SNELL_PSK:-$(openssl rand -hex 32)}"
CONFIG_DIR="/etc/surge-nodes"
CONFIG_PATH="$CONFIG_DIR/snell.conf"
BIN_DIR="/opt/snell"
install -d -m 0700 "$CONFIG_DIR" "$BIN_DIR"

archive="$(mktemp)"
curl -fsSL "https://dl.nssurge.com/snell/snell-server-v$SNELL_VERSION-linux-$snell_arch.zip" -o "$archive"
unzip -qo "$archive" -d "$BIN_DIR"
rm -f "$archive"
install -m 0755 "$BIN_DIR/snell-server" /usr/local/bin/snell-server

cat >"$CONFIG_PATH" <<EOF
[snell-server]
listen = 0.0.0.0:$PORT
psk = $SNELL_PSK
ipv6 = false
EOF
chmod 0600 "$CONFIG_PATH"
cat >/etc/systemd/system/surge-snell.service <<EOF
[Unit]
Description=Surge node Snell
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snell-server -c $CONFIG_PATH
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
write_secret_env snell "SERVER_NAME=$SERVER_NAME" "PORT=$PORT" "SNELL_PSK=$SNELL_PSK" "SNELL_VERSION=$SNELL_VERSION"
systemctl daemon-reload
systemctl enable --now surge-snell.service
open_ufw_port_if_requested tcp
bash "$SCRIPT_DIR/../Subscription/generate-surge-subscription.sh"
echo "部署完成。凭据已写入 $NODE_ROOT/snell.env；未在终端输出。私有订阅已在 VPS 本地重新生成。"
