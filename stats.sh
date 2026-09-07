#!/bin/bash
# Emits one JSON snapshot of system metrics on stdout.
#
# CPU and network are rates, so they need two samples. Rather than sleeping
# (which would stall the poll), the previous sample is kept in a state file and
# each run reports the delta since the last one. The first run after a cold
# start reports 0 for those two and is correct from the second poll onward.

set -uo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/loadout-stats.state"

read_prev() { [[ -f $STATE ]] && cat "$STATE" || echo ""; }

prev="$(read_prev)"

# ---- CPU ---------------------------------------------------------------
read -r _ u n s i io irq sirq st _ < /proc/stat
cpu_busy=$((u + n + s + irq + sirq + st))
cpu_total=$((cpu_busy + i + io))

cpu_pct=0
prev_busy="$(awk '/^cpu /{print $2}' <<< "$prev")"
prev_total="$(awk '/^cpu /{print $3}' <<< "$prev")"
if [[ -n ${prev_busy:-} && -n ${prev_total:-} ]]; then
  d_busy=$((cpu_busy - prev_busy))
  d_total=$((cpu_total - prev_total))
  ((d_total > 0)) && cpu_pct=$((100 * d_busy / d_total))
fi

cores="$(nproc 2>/dev/null || echo 1)"
read -r load1 _ < /proc/loadavg

# ---- Memory ------------------------------------------------------------
mem_total_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
mem_avail_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
mem_used_kb=$((mem_total_kb - mem_avail_kb))
mem_pct=$((mem_total_kb > 0 ? 100 * mem_used_kb / mem_total_kb : 0))

swap_total_kb="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)"
swap_free_kb="$(awk '/^SwapFree:/{print $2}' /proc/meminfo)"
swap_used_kb=$((swap_total_kb - swap_free_kb))
swap_pct=$((swap_total_kb > 0 ? 100 * swap_used_kb / swap_total_kb : 0))

# ---- Disk (root filesystem) -------------------------------------------
read -r disk_total_k disk_used_k disk_pct < <(
  df -Pk / | awk 'NR==2{gsub(/%/,"",$5); print $2, $3, $5}'
)

# ---- Network (sum of physical interfaces) ------------------------------
rx_now=0; tx_now=0
for iface in /sys/class/net/*; do
  name="$(basename "$iface")"
  [[ $name == lo || $name == docker* || $name == veth* || $name == br-* ]] && continue
  [[ -r $iface/statistics/rx_bytes ]] || continue
  rx_now=$((rx_now + $(<"$iface/statistics/rx_bytes")))
  tx_now=$((tx_now + $(<"$iface/statistics/tx_bytes")))
done

now_ms=$(( $(date +%s%N) / 1000000 ))
rx_rate=0; tx_rate=0
prev_net="$(awk '/^net /{print $2, $3, $4}' <<< "$prev")"
if [[ -n $prev_net ]]; then
  read -r prev_rx prev_tx prev_ms <<< "$prev_net"
  d_ms=$((now_ms - prev_ms))
  if ((d_ms > 0)); then
    rx_rate=$(( (rx_now - prev_rx) * 1000 / d_ms ))
    tx_rate=$(( (tx_now - prev_tx) * 1000 / d_ms ))
    ((rx_rate < 0)) && rx_rate=0
    ((tx_rate < 0)) && tx_rate=0
  fi
fi

# ---- GPU ---------------------------------------------------------------
gpu_pct=-1; gpu_mem_pct=-1; gpu_name=""; gpu_temp=-1
if command -v nvidia-smi >/dev/null 2>&1; then
  read -r gpu_pct gpu_mem_used gpu_mem_total gpu_temp gpu_name < <(
    nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,name \
      --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ','
  )
  gpu_pct="${gpu_pct:--1}"
  [[ -n ${gpu_mem_total:-} && ${gpu_mem_total:-0} -gt 0 ]] &&
    gpu_mem_pct=$((100 * gpu_mem_used / gpu_mem_total))
else
  # AMD exposes a busy-percent file; Intel has no simple equivalent.
  for card in /sys/class/drm/card*/device/gpu_busy_percent; do
    [[ -r $card ]] || continue
    gpu_pct="$(<"$card")"
    break
  done
fi

# ---- Temperature -------------------------------------------------------
cpu_temp=-1
for zone in /sys/class/thermal/thermal_zone*; do
  [[ -r $zone/type && -r $zone/temp ]] || continue
  case "$(<"$zone/type")" in
    x86_pkg_temp|k10temp|coretemp|acpitz)
      cpu_temp=$(( $(<"$zone/temp") / 1000 ))
      break
      ;;
  esac
done

# ---- Uptime ------------------------------------------------------------
read -r up_seconds _ < /proc/uptime
up_seconds="${up_seconds%.*}"

# Persist this sample for the next run's deltas.
{
  echo "cpu $cpu_busy $cpu_total"
  echo "net $rx_now $tx_now $now_ms"
} > "$STATE"

jq -n \
  --argjson cpu "$cpu_pct" --argjson cores "$cores" --arg load "$load1" \
  --argjson cpuTemp "$cpu_temp" \
  --argjson memUsed "$mem_used_kb" --argjson memTotal "$mem_total_kb" --argjson memPct "$mem_pct" \
  --argjson swapUsed "$swap_used_kb" --argjson swapTotal "$swap_total_kb" --argjson swapPct "$swap_pct" \
  --argjson diskUsed "${disk_used_k:-0}" --argjson diskTotal "${disk_total_k:-0}" --argjson diskPct "${disk_pct:-0}" \
  --argjson rx "$rx_rate" --argjson tx "$tx_rate" \
  --argjson gpu "${gpu_pct:--1}" --argjson gpuMem "${gpu_mem_pct:--1}" --argjson gpuTemp "${gpu_temp:--1}" \
  --arg gpuName "${gpu_name:-}" \
  --argjson uptime "$up_seconds" \
  '{
    cpu:      {percent:$cpu, cores:$cores, load:($load|tonumber), temp:$cpuTemp},
    memory:   {usedKb:$memUsed, totalKb:$memTotal, percent:$memPct},
    swap:     {usedKb:$swapUsed, totalKb:$swapTotal, percent:$swapPct},
    disk:     {usedKb:$diskUsed, totalKb:$diskTotal, percent:$diskPct},
    network:  {rxBytesPerSec:$rx, txBytesPerSec:$tx},
    gpu:      {percent:$gpu, memPercent:$gpuMem, temp:$gpuTemp, name:$gpuName},
    uptimeSeconds:$uptime
  }'
