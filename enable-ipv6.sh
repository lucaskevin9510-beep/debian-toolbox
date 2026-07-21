#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行此脚本"
    exit 1
fi

CONF="/etc/sysctl.d/99-disable-ipv6.conf"

echo "======================================"
echo "           恢复 IPv6"
echo "======================================"

# 删除永久禁用 IPv6 的配置
if [ -f "$CONF" ]; then
    rm -f "$CONF"
    echo "[1/3] 已删除永久禁用配置：$CONF"
else
    echo "[1/3] 未发现永久禁用配置"
fi

# 恢复全局及默认 IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null

# 恢复当前已存在网络接口的 IPv6
for iface in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    [ -f "$iface" ] && echo 0 > "$iface" || true
done

echo "[2/3] IPv6 内核功能已重新启用"

# 重新加载 sysctl 配置
sysctl --system >/dev/null 2>&1 || true

echo "[3/3] 当前状态："
echo "net.ipv6.conf.all.disable_ipv6     = $(sysctl -n net.ipv6.conf.all.disable_ipv6)"
echo "net.ipv6.conf.default.disable_ipv6 = $(sysctl -n net.ipv6.conf.default.disable_ipv6)"

echo
echo "当前 IPv6 地址："
ip -6 addr show || true

echo
echo "======================================"
echo " IPv6 已恢复启用"
echo " 如未立即获取公网 IPv6，请重启 VPS"
echo "======================================"
