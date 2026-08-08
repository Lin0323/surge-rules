#!/usr/bin/env bash
# 在 VPS 本地生成私有 Surge 订阅；不监听端口、不上传 GitHub、不输出任何凭据。
set -euo pipefail
umask 077

[[ "$(id -u)" -eq 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
NODE_ROOT="/etc/surge-nodes"
OUTPUT_DIR="${OUTPUT_DIR:-/var/lib/surge-subscription}"
OUTPUT_FILE="$OUTPUT_DIR/Surge.conf"

safe_source() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  [[ "$(stat -c '%U' "$file")" == "root" ]] || { echo "拒绝读取非 root 所有的凭据文件：$file" >&2; exit 1; }
  [[ "$(stat -c '%a' "$file")" == "600" ]] || { echo "拒绝读取权限非 0600 的凭据文件：$file" >&2; exit 1; }
  source "$file"
}

install -d -m 0700 "$OUTPUT_DIR"
tmp="$(mktemp "$OUTPUT_DIR/.Surge.conf.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
policies=()

{
  if [[ -n "${SUBSCRIPTION_URL:-}" ]]; then
    printf '%s\n' "#!MANAGED-CONFIG $SUBSCRIPTION_URL interval=86400 strict=false"
  fi
  printf '%s\n' "# 私有订阅：由本 VPS 本地生成。不得提交 GitHub 或公开分享。"
  printf '%s\n\n' "[Proxy]"

  if safe_source "$NODE_ROOT/shadowtls.env"; then
    printf '%s\n' "SS2022-ShadowTLS = ss, $SERVER_NAME, $PORT, encrypt-method=2022-blake3-aes-256-gcm, password=$SS_PASSWORD, shadow-tls-password=$SHADOWTLS_PASSWORD, shadow-tls-sni=$HANDSHAKE_SERVER:443, shadow-tls-version=3, udp-relay=false"
    policies+=("SS2022-ShadowTLS")
  fi
  if safe_source "$NODE_ROOT/anytls.env"; then
    printf '%s\n' "AnyTLS = anytls, $SERVER_NAME, $PORT, password=$ANYTLS_PASSWORD, sni=$SERVER_NAME, skip-cert-verify=false"
    policies+=("AnyTLS")
  fi
  if safe_source "$NODE_ROOT/hysteria2.env"; then
    printf '%s\n' "Hysteria2 = hysteria2, $SERVER_NAME, $PORT, password=$HYSTERIA2_PASSWORD, sni=$SERVER_NAME, skip-cert-verify=false"
    policies+=("Hysteria2")
  fi
  if safe_source "$NODE_ROOT/snell.env"; then
    printf '%s\n' "Snell = snell, $SERVER_NAME, $PORT, psk=$SNELL_PSK, version=$SNELL_VERSION"
    policies+=("Snell")
  fi

  (( ${#policies[@]} > 0 )) || { echo "未找到已部署节点，拒绝生成空订阅。" >&2; exit 1; }
  printf '\n[Proxy Group]\nAuto = url-test'
  for policy in "${policies[@]}"; do
    printf ', %s' "$policy"
  done
  printf '%s\n' ", url=http://www.gstatic.com/generate_204, interval=600, tolerance=100, timeout=8, evaluate-before-use=true"
  cat <<'EOF'
Proxy = select, Auto, DIRECT
AI = select, Proxy, DIRECT
Media = select, Proxy, DIRECT
Developer = select, Proxy, DIRECT
Apple = select, Proxy, DIRECT
Backup = fallback, Auto, DIRECT, url=http://www.gstatic.com/generate_204, interval=600, timeout=8
EOF
} >"$tmp"

chmod 0600 "$tmp"
mv -f "$tmp" "$OUTPUT_FILE"
trap - EXIT
echo "私有订阅已生成到 $OUTPUT_FILE（0600，仅 root 可读）。未启动公网服务，未显示订阅内容。"
