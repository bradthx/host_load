# server_strain

A single-number system load indicator for Linux. Outputs one integer representing
how hard the system is working, calibrated so that **100 = fully utilized with no
bottlenecks** and values **above 100 indicate bottlenecks are forming**.

```
$ ./server_strain.sh
42
```

## Scale

| Range | Meaning |
|-------|---------|
| 0–30 | Near idle |
| 30–70 | Moderate load |
| 70–100 | Heavy but healthy utilization |
| >100 | Bottleneck detected — something is saturated |

## Usage

```bash
./server_strain.sh [interval]
```

`interval` is the CPU sampling window in seconds (default: `1`). A longer interval
produces a more stable reading on bursty workloads.

```bash
./server_strain.sh 5    # average over 5 seconds
```

The script only uses `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, `awk`, and
`nproc` — all present on essentially every Linux distribution. No root required.

## How it works

### Step 1 — CPU utilization & I/O wait

The kernel exposes cumulative CPU jiffie counts in `/proc/stat`. The script reads
that file twice, separated by `interval` seconds, and computes the delta to get a
real-time percentage:

```
cpu_busy% = 100 × (total_delta − idle_delta − iowait_delta) / total_delta
iowait%   = 100 × iowait_delta / total_delta
```

Separating iowait from busy time matters: a CPU blocked on disk I/O shows up as
"idle" in the busy figure but as iowait here, so both signals are captured.

### Step 2 — Memory pressure

Read from `/proc/meminfo`:

```
mem_used% = 100 × (MemTotal − MemAvailable) / MemTotal
```

`MemAvailable` (not `MemFree`) is used because the kernel reclaims page cache on
demand. This avoids false pressure readings on systems that use memory for caching.

Swap usage is tracked separately for the bottleneck penalty in step 5.

### Step 3 — Normalized load average

The 1-minute load average from `/proc/loadavg` is divided by the number of logical
CPU cores (`nproc`):

```
load% = (load_1m / cores) × 100
```

A value of 100% means exactly one runnable task per core on average — full but
not over-committed.

### Step 4 — Base strain (weighted average)

The four signals are blended into a single 0–100 base score:

| Signal | Weight | Rationale |
|--------|--------|-----------|
| CPU busy % | 40% | Primary throughput indicator |
| Normalized load % | 30% | Captures scheduling demand including disk/network wait |
| Memory used % | 20% | Working-set pressure |
| I/O wait % | 10% | Disk latency already partially reflected in load |

```
base_strain = cpu×0.40 + load×0.30 + mem×0.20 + iowait×0.10
```

On a perfectly idle system this approaches 0. On a system where every resource is
fully saturated but nothing is queuing, it approaches 100.

### Step 5 — Bottleneck penalties

When resources are over-committed, penalties are added on top of the base score,
which can push `server_strain` above 100:

| Condition | Formula | What it signals |
|-----------|---------|----------------|
| Load average > core count | `+(excess/cores) × 30` | Tasks queuing for CPU — scheduler is backlogged |
| I/O wait > 20% | `+(iowait − 20) / 2` | Disk is a throughput bottleneck |
| Swap used > 5% | `+(swap_pct − 5) / 2` | Physical RAM exhausted, paging to disk |

A strain of 120, for example, means the system is not just fully utilized but is
actively building up queues — response times will be degrading.

## Dependencies

| Tool | Source |
|------|--------|
| `bash` | Shell interpreter |
| `awk` | Field parsing and floating-point math |
| `nproc` | Core count (falls back to `/proc/cpuinfo`) |
| `/proc/stat` | CPU jiffie counters |
| `/proc/meminfo` | Memory and swap figures |
| `/proc/loadavg` | Load average |

All dependencies are part of the Linux base system.
