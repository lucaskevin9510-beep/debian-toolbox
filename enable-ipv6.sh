#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行此脚本"
    exit 1
fi

CONF="/etc/sysctl.d/99-disable-ipv6.conf"
REPORT="/root/ipv6-network-status-after-reboot.txt"
PENDING="/var/lib/ipv6-restore-status.pending"
POST_SCRIPT="/usr/local/sbin/ipv6-postboot-status.sh"
SERVICE="/etc/systemd/system/ipv6-postboot-status.service"
PROFILE_SCRIPT="/etc/profile.d/show-ipv6-status-once.sh"

echo "======================================"
echo "            恢复 IPv6"
echo "======================================"

#
# 1. 删除永久禁用 IPv6 配置
#
if [ -f "$CONF" ]; then
    rm -f "$CONF"
    echo "[1/5] 已删除永久禁用 IPv6 配置："
    echo "      $CONF"
else
    echo "[1/5] 未发现永久禁用 IPv6 配置"
fi

#
# 2. 立即恢复 IPv6
#
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null

# 恢复当前所有网络接口的 IPv6
for iface in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    if [ -f "$iface" ]; then
        echo 0 > "$iface" 2>/dev/null || true
    fi
done

echo "[2/5] IPv6 已立即恢复"

#
# 创建重启后的网络状态检测脚本
#
cat > "$POST_SCRIPT" <<'EOF'
#!/usr/bin/env bash

REPORT="/root/ipv6-network-status-after-reboot.txt"
PENDING="/var/lib/ipv6-restore-status.pending"

# 给网络接口和 IPv6 RA/DHCPv6 一点初始化时间
sleep 5

{
    echo
    echo "======================================"
    echo "       VPS 重启后的网络状态"
    echo "======================================"
    echo
    echo "检测时间：$(date)"
    echo

    echo "======================================"
    echo "          当前 IPv4 地址"
    echo "======================================"

    IPV4=$(ip -o -4 addr show scope global 2>/dev/null)

    if [ -n "$IPV4" ]; then
        echo "$IPV4"
    else
        echo "未检测到公网 IPv4 地址"
    fi

    echo
    echo "======================================"
    echo "        IPv4 默认路由"
    echo "======================================"

    IPV4_ROUTE=$(ip -4 route show default 2>/dev/null)

    if [ -n "$IPV4_ROUTE" ]; then
        echo "$IPV4_ROUTE"
    else
        echo "未检测到 IPv4 默认路由"
    fi

    echo
    echo "======================================"
    echo "          当前 IPv6 地址"
    echo "======================================"

    IPV6=$(ip -o -6 addr show scope global 2>/dev/null)

    if [ -n "$IPV6" ]; then
        echo "$IPV6"
    else
        echo "未检测到公网 IPv6 地址"
    fi

    echo
    echo "======================================"
    echo "        IPv6 默认路由"
    echo "======================================"

    IPV6_ROUTE=$(ip -6 route show default 2>/dev/null)

    if [ -n "$IPV6_ROUTE" ]; then
        echo "$IPV6_ROUTE"
    else
        echo "未检测到 IPv6 默认路由"
    fi

    echo
    echo "======================================"
    echo "        IPv6 内核开关状态"
    echo "======================================"

    ALL_STATUS=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    DEFAULT_STATUS=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null)

    echo "all.disable_ipv6     = $ALL_STATUS"
    echo "default.disable_ipv6 = $DEFAULT_STATUS"

    echo

    if [ "$ALL_STATUS" = "0" ] && [ "$DEFAULT_STATUS" = "0" ]; then
        echo "IPv6 内核状态：已启用"
    else
        echo "IPv6 内核状态：异常，可能仍处于禁用状态"
    fi

    echo
    echo "======================================"
    echo "           检测完成"
    echo "======================================"
    echo

} > "$REPORT"

rm -f "$PENDING"

# 任务只执行一次
systemctl disable ipv6-postboot-status.service >/dev/null 2>&1 || true
EOF

chmod +x "$POST_SCRIPT"

#
# 创建一次性 systemd 服务
#
cat > "$SERVICE" <<EOF
[Unit]
Description=IPv6 Post-Reboot Network Status Check
Wants=network-online.target
After=network-online.target
ConditionPathExists=$PENDING

[Service]
Type=oneshot
ExecStart=$POST_SCRIPT

[Install]
WantedBy=multi-user.target
EOF

#
# 创建下次 SSH 登录时自动显示结果的脚本
#
cat > "$PROFILE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

REPORT="/root/ipv6-network-status-after-reboot.txt"

# 仅 root 用户显示
if [ "$(id -u)" -eq 0 ]; then

    # 等待重启后的检测任务完成，最长约 15 秒
    for i in $(seq 1 15); do
        if [ -f "$REPORT" ]; then
            break
        fi
        sleep 1
    done

    if [ -f "$REPORT" ]; then
        cat "$REPORT"

        echo "以上为 VPS 重启后的 IPv4 / IPv6 网络状态。"
        echo

        # 显示一次后自动清理
        rm -f "$REPORT"
        rm -f /etc/profile.d/show-ipv6-status-once.sh
        rm -f /usr/local/sbin/ipv6-postboot-status.sh
        rm -f /etc/systemd/system/ipv6-postboot-status.service

        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
fi
EOF

chmod +x "$PROFILE_SCRIPT"

#
# 设置一次性任务标记
#
touch "$PENDING"

systemctl daemon-reload
systemctl enable ipv6-postboot-status.service >/dev/null

echo "[3/5] 已创建重启后的 IPv4 / IPv6 自动检测任务"
echo "[4/5] 重启后重新 SSH 登录，将自动显示网络状态"

echo
echo "======================================"
echo " VPS 将在 5 秒后自动重启"
echo " 当前 SSH 连接将断开"
echo " 重启后请重新 SSH 登录"
echo " 登录后将自动显示："
echo "  - IPv4 地址"
echo "  - IPv6 地址"
echo "  - IPv4 默认路由"
echo "  - IPv6 默认路由"
echo "  - IPv6 内核开关状态"
echo "======================================"
echo

for i in 5 4 3 2 1; do
    echo -ne "\r将在 $i 秒后重启..."
    sleep 1
done

echo
echo "[5/5] 正在重启 VPS..."

sync
systemctl reboot
