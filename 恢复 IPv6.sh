#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

rm -f /etc/sysctl.d/99-disable-ipv6.conf

sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null

echo "IPv6 已恢复启用。"
echo "部分网络接口可能需要重启网络或重启 VPS 才能重新获取 IPv6 地址。"
