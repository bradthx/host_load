#!/bin/bash
# server_strain -- System load indicator
#   0   = near idle
#   100 = fully utilized, no bottlenecks
#  >100 = bottlenecks forming (queuing, iowait, swap pressure)
# Usage: server_strain [sample_interval_seconds]

INTERVAL=${1:-1}

# 1. CPU utilization & iowait (two-sample delta)
# /proc/stat fields: user nice sys idle iowait irq softirq
cpu_read() { awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8; exit}' /proc/stat; }

snap1=$(cpu_read)
sleep "$INTERVAL"
snap2=$(cpu_read)

read -r u1 n1 s1 i1 w1 q1 x1 <<< "$snap1"
read -r u2 n2 s2 i2 w2 q2 x2 <<< "$snap2"

dt=$(( (u2+n2+s2+i2+w2+q2+x2) - (u1+n1+s1+i1+w1+q1+x1) ))
(( dt <= 0 )) && dt=1

cpu_pct=$(( 100 * (dt - (i2-i1) - (w2-w1)) / dt ))
iowait_pct=$(( 100 * (w2-w1) / dt ))

# 2. Memory pressure (MemAvailable accounts for reclaimable caches)
mem_total=$(awk '/^MemTotal/{print $2; exit}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable/{print $2; exit}' /proc/meminfo)
(( mem_total <= 0 )) && mem_total=1
mem_pct=$(( 100 * (mem_total - mem_avail) / mem_total ))

swap_total=$(awk '/^SwapTotal/{print $2; exit}' /proc/meminfo)
swap_free=$(awk '/^SwapFree/{print $2; exit}' /proc/meminfo)
swap_used=$(( swap_total - swap_free ))

# 3. Load average vs. CPU core count (1.0/core = 100%)
cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
(( cores <= 0 )) && cores=1
load1m=$(awk '{print $1}' /proc/loadavg)
load_pct=$(awk -v la="$load1m" -v c="$cores" 'BEGIN { printf "%d", (la/c)*100 }')

# 4. Base strain: weighted average (0-100 target)
#    cpu 40% | load 30% | mem 20% | iowait 10%
strain=$(awk \
    -v cpu="$cpu_pct"    \
    -v la="$load_pct"    \
    -v mem="$mem_pct"    \
    -v io="$iowait_pct"  \
    'BEGIN { printf "%d", cpu*0.40 + la*0.30 + mem*0.20 + io*0.10 }')

# 5. Bottleneck penalties (push strain above 100)

# Load > cores: tasks actively queuing for CPU
load_penalty=$(awk -v la="$load1m" -v c="$cores" \
    'BEGIN { e=la-c; printf "%d", (e>0) ? (e/c)*30 : 0 }')

# IOWait > 20%: disk is a meaningful bottleneck
iowait_penalty=0
(( iowait_pct > 20 )) && iowait_penalty=$(( (iowait_pct - 20) / 2 ))

# Swap >5% in use: memory genuinely exhausted
swap_penalty=0
if (( swap_total > 0 )); then
    swap_pct=$(( 100 * swap_used / swap_total ))
    (( swap_pct > 5 )) && swap_penalty=$(( (swap_pct - 5) / 2 ))
fi

strain=$(( strain + load_penalty + iowait_penalty + swap_penalty ))

echo "$strain"
