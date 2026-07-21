#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    echo "例如: sudo bash $0"
    exit 1
fi

CONF="/etc/sysctl.d/99-disable-ipv6.conf"

echo "正在永久禁用 IPv6..."

cat > "$CONF" <<'EOF'
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# 立即应用
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null

echo
echo "IPv6 状态："
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv6.conf.default.disable_ipv6

echo
echo "完成：IPv6 已立即禁用，并将在重启后保持禁用。"
