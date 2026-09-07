#!/bin/bash
# Emits one JSON snapshot of system metrics on stdout.
#
# CPU, network and disk are rates, so they need two samples. Rather than
# sleeping (which would stall the poll), the previous sample is kept in a state
# file and each run reports the delta since the last one. The first run after a
# cold start reports 0 for those and is correct from the second poll onward.

set -uo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/loadout-stats.state"

prev=""
[[ -f $STATE ]] && prev="$(<"$STATE")"

# ---- CPU: overall and per core ------------------------------------------
# One line per /proc/stat cpu row: "<name> <busy> <total>", in jiffies.
cpu_now="$(awk '/^cpu[0-9]* / {
  busy = $2 + $3 + $4 + $7 + $8 + $9
  total = busy + $5 + $6
  print $1, busy, total
}' /proc/stat)"

prev_cpu="$(awk '/^stat /{print $2, $3, $4}' <<< "$prev")"

# Prints "<overall>\n[<core0>,<core1>,...]" — percentages since the last run.
cpu_calc="$(awk -v prev="$prev_cpu" '
  BEGIN {
    n = split(prev, lines, "\n")
    for (i = 1; i <= n; i++) {
      split(lines[i], f, " ")
      if (f[1] != "") { pb[f[1]] = f[2]; pt[f[1]] = f[3] }
    }
  }
  {
    pct = 0
    if ($1 in pt) {
      dt = $3 - pt[$1]; db = $2 - pb[$1]
      if (dt > 0 && db >= 0) pct = int(100 * db / dt + 0.5)
      if (pct > 100) pct = 100
    }
    if ($1 == "cpu") overall = pct
    else cores[++c] = pct
  }
  END {
    print overall + 0
    printf "["
    for (i = 1; i <= c; i++) printf "%s%d", (i > 1 ? "," : ""), cores[i]
    printf "]\n"
  }' <<< "$cpu_now")"
cpu_pct="${cpu_calc%%$'\n'*}"
cores_json="${cpu_calc#*$'\n'}"

cores="$(nproc 2>/dev/null || echo 1)"
read -r load1 load5 load15 _ < /proc/loadavg

# ---- Memory --------------------------------------------------------------
mem_total_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
mem_avail_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
mem_used_kb=$((mem_total_kb - mem_avail_kb))
mem_pct=$((mem_total_kb > 0 ? 100 * mem_used_kb / mem_total_kb : 0))

swap_total_kb="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)"
swap_free_kb="$(awk '/^SwapFree:/{print $2}' /proc/meminfo)"
swap_used_kb=$((swap_total_kb - swap_free_kb))
swap_pct=$((swap_total_kb > 0 ? 100 * swap_used_kb / swap_total_kb : 0))

# ---- Disk capacity (root filesystem) and throughput ----------------------
read -r disk_total_k disk_used_k disk_pct < <(
  df -Pk / | awk 'NR==2{gsub(/%/,"",$5); print $2, $3, $5}'
)

# The physical disk behind /, for the label. Walk the inverse tree so LUKS
# and LVM mappers resolve to the drive underneath: omarchy_root -> nvme0n1.
root_src="$(findmnt -no SOURCE / 2>/dev/null)"
root_src="${root_src%%\[*}"   # btrfs reports /dev/x[/@]; drop the subvolume
disk_name="$(lsblk -slno NAME "$root_src" 2>/dev/null | tail -1)"
[[ -n $disk_name ]] || disk_name="${root_src##*/}"

# Sectors read/written across whole physical devices (partitions would
# double-count). /proc/diskstats sectors are always 512 bytes.
read -r rd_now wr_now < <(awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+|mmcblk[0-9]+)$/ {
  r += $6; w += $10
} END { print r + 0, w + 0 }' /proc/diskstats)

# ---- Network (sum of physical interfaces) --------------------------------
rx_now=0; tx_now=0
for iface in /sys/class/net/*; do
  name="$(basename "$iface")"
  [[ $name == lo || $name == docker* || $name == veth* || $name == br-* ]] && continue
  [[ -r $iface/statistics/rx_bytes ]] || continue
  rx_now=$((rx_now + $(<"$iface/statistics/rx_bytes")))
  tx_now=$((tx_now + $(<"$iface/statistics/tx_bytes")))
done
net_name="$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')"

now_ms=$(( $(date +%s%N) / 1000000 ))

# rate <now> <prev> <elapsed_ms> -> per-second rate, clamped at zero.
rate() {
  local d=$(( $1 - $2 ))
  (( $3 > 0 && d > 0 )) && echo $(( d * 1000 / $3 )) || echo 0
}

rx_rate=0; tx_rate=0; rd_rate=0; wr_rate=0
prev_ms="$(awk '/^time /{print $2}' <<< "$prev")"
if [[ -n $prev_ms ]]; then
  d_ms=$((now_ms - prev_ms))
  read -r prev_rx prev_tx < <(awk '/^net /{print $2, $3}' <<< "$prev")
  read -r prev_rd prev_wr < <(awk '/^disk /{print $2, $3}' <<< "$prev")
  if [[ -n ${prev_rx:-} ]]; then
    rx_rate="$(rate "$rx_now" "$prev_rx" "$d_ms")"
    tx_rate="$(rate "$tx_now" "$prev_tx" "$d_ms")"
  fi
  if [[ -n ${prev_rd:-} ]]; then
    rd_rate="$(rate $((rd_now * 512)) $((prev_rd * 512)) "$d_ms")"
    wr_rate="$(rate $((wr_now * 512)) $((prev_wr * 512)) "$d_ms")"
  fi
fi

# ---- GPU -----------------------------------------------------------------
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

# ---- Temperature ---------------------------------------------------------
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

# ---- Uptime and identity -------------------------------------------------
read -r up_seconds _ < /proc/uptime
up_seconds="${up_seconds%.*}"
host="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)"

# Persist this sample for the next run's deltas.
{
  echo "time $now_ms"
  sed 's/^/stat /' <<< "$cpu_now"
  echo "net $rx_now $tx_now"
  echo "disk $rd_now $wr_now"
} > "$STATE"

jq -n \
  --argjson cpu "$cpu_pct" --argjson cores "$cores" --argjson perCore "$cores_json" \
  --arg load1 "$load1" --arg load5 "$load5" --arg load15 "$load15" \
  --argjson cpuTemp "$cpu_temp" \
  --argjson memUsed "$mem_used_kb" --argjson memTotal "$mem_total_kb" --argjson memPct "$mem_pct" \
  --argjson swapUsed "$swap_used_kb" --argjson swapTotal "$swap_total_kb" --argjson swapPct "$swap_pct" \
  --argjson diskUsed "${disk_used_k:-0}" --argjson diskTotal "${disk_total_k:-0}" --argjson diskPct "${disk_pct:-0}" \
  --arg diskName "$disk_name" --argjson rd "$rd_rate" --argjson wr "$wr_rate" \
  --argjson rx "$rx_rate" --argjson tx "$tx_rate" --arg netName "$net_name" \
  --argjson gpu "${gpu_pct:--1}" --argjson gpuMem "${gpu_mem_pct:--1}" --argjson gpuTemp "${gpu_temp:--1}" \
  --arg gpuName "${gpu_name:-}" \
  --argjson uptime "$up_seconds" --arg host "$host" \
  '{
    cpu:      {percent:$cpu, cores:$cores, perCore:$perCore, temp:$cpuTemp,
               load:($load1|tonumber), load5:($load5|tonumber), load15:($load15|tonumber)},
    memory:   {usedKb:$memUsed, totalKb:$memTotal, percent:$memPct},
    swap:     {usedKb:$swapUsed, totalKb:$swapTotal, percent:$swapPct},
    disk:     {usedKb:$diskUsed, totalKb:$diskTotal, percent:$diskPct, name:$diskName,
               readBytesPerSec:$rd, writeBytesPerSec:$wr},
    network:  {rxBytesPerSec:$rx, txBytesPerSec:$tx, name:$netName},
    gpu:      {percent:$gpu, memPercent:$gpuMem, temp:$gpuTemp, name:$gpuName},
    uptimeSeconds:$uptime, hostname:$host
  }'
