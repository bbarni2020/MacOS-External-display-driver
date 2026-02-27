#!/bin/sh
set -e

echo "Applying low-latency Ethernet tuning (temporary until reboot)..."

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./tune-pi-lowlatency.sh"
  exit 1
fi

IFACE="${1:-eth0}"

if [ ! -d "/sys/class/net/$IFACE" ]; then
  echo "Interface $IFACE not found"
  ip -br link
  exit 2
fi

sysctl -w net.core.rmem_max=67108864
sysctl -w net.core.wmem_max=67108864
sysctl -w net.core.netdev_max_backlog=5000
sysctl -w net.ipv4.tcp_rmem='4096 87380 33554432'
sysctl -w net.ipv4.tcp_wmem='4096 65536 33554432'
sysctl -w net.ipv4.tcp_low_latency=1
sysctl -w net.ipv4.tcp_mtu_probing=1

if command -v ethtool >/dev/null 2>&1; then
  ethtool -K "$IFACE" gro off gso off tso off >/dev/null 2>&1 || true
  ethtool -C "$IFACE" rx-usecs 0 tx-usecs 0 >/dev/null 2>&1 || true
fi

if [ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -w "$cpu/cpufreq/scaling_governor" ] && echo performance > "$cpu/cpufreq/scaling_governor" || true
  done
fi

if command -v vcgencmd >/dev/null 2>&1; then
  echo "CPU freq: $(vcgencmd measure_clock arm 2>/dev/null || true)"
  echo "CPU temp: $(vcgencmd measure_temp 2>/dev/null || true)"
fi

echo "Done. Re-run after reboot, or persist via /etc/sysctl.d and systemd."