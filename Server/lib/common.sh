#!/usr/bin/env bash
set -euo pipefail
umask 077

NODE_ROOT="/etc/surge-nodes"

require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || { echo "缺少环境变量：$name" >&2; exit 1; }
}

validate_host_and_port() {
  [[ "${SERVER_NAME:-}" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "SERVER_NAME 必须是域名或 IP。" >&2; exit 1; }
  [[ "${PORT:-}" =~ ^[0-9]{1,5}$ ]] && (( PORT > 0 && PORT < 65536 )) || { echo "PORT 不合法。" >&2; exit 1; }
}

assert_port_free() {
  local protocol="$1"
  local options
  case "$protocol" in
    tcp) options="-H -ltn" ;;
    udp) options="-H -lun" ;;
    *) echo "未知传输协议：$protocol" >&2; exit 1 ;;
  esac
  if ss $options | awk '{print $4}' | grep -Eq "[:.]$PORT$"; then
    echo "端口 $PORT/$protocol 已被占用；为避免覆盖现有服务，脚本已停止。" >&2
    exit 1
  fi
}

random_b64() {
  openssl rand -base64 "$1" | tr -d '\n'
}

ensure_sing_box() {
  if command -v sing-box >/dev/null 2>&1; then
    return
  fi
  apt-get update
  apt-get install -y ca-certificates curl openssl
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod a+r /etc/apt/keyrings/sagernet.asc
  cat >/etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
  apt-get update
  apt-get install -y sing-box
}

require_tls_files() {
  CERT_PATH="${CERT_PATH:-/etc/letsencrypt/live/$SERVER_NAME/fullchain.pem}"
  KEY_PATH="${KEY_PATH:-/etc/letsencrypt/live/$SERVER_NAME/privkey.pem}"
  [[ -r "$CERT_PATH" && -r "$KEY_PATH" ]] || {
    echo "未找到可读 TLS 证书。请先签发证书，或设置 CERT_PATH 与 KEY_PATH。" >&2
    exit 1
  }
}

write_secret_env() {
  local name="$1"
  shift
  install -d -m 0700 "$NODE_ROOT"
  local target="$NODE_ROOT/$name.env"
  : >"$target"
  chmod 0600 "$target"
  for item in "$@"; do
    printf '%s\n' "$item" >>"$target"
  done
}

install_sing_box_service() {
  local name="$1"
  local config="$2"
  cat >"/etc/systemd/system/surge-$name.service" <<EOF
[Unit]
Description=Surge node $name
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/sing-box run -c $config
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "surge-$name.service"
}

open_ufw_port_if_requested() {
  local protocol="$1"
  if [[ "${OPEN_FIREWALL:-0}" == "1" ]]; then
    command -v ufw >/dev/null 2>&1 || { echo "未安装 UFW，未修改防火墙。" >&2; return; }
    ufw allow "$PORT/$protocol"
  fi
}
