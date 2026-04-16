# server_strain

![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![Dependencies](https://img.shields.io/badge/dependencies-none-lightgrey)
![License](https://img.shields.io/badge/license-MIT-orange)

A portable system strain indicator for Linux. Run it, get one integer back indicating the realtive strain on the server.

> **0** = near idle &nbsp;|&nbsp; **100** = fully utilized, no bottlenecks &nbsp;|&nbsp; **> 100** = over utilization

```
$ ./server_strain.sh
42
```

---

## Scale

| Range   | Meaning                                        |
|---------|------------------------------------------------|
| 0 to 30   | Near idle                                     |
| 30 to 70  | Moderate load                                 |
| 70 to 100 | Heavy but healthy utilization, within limits  |
| > 100     | Bottleneck detected, something is saturated   |

---

## Usage

```bash
# Default: 1-second CPU sample window
./server_strain.sh

# Custom sample interval (seconds) more stable on bursty workloads
./server_strain.sh 5
```

No root required. The script only reads from `/proc` and calls `awk` / `nproc`,
which are present on essentially every Linux distribution.

---

## How it works

`server_strain` collects four signals, blends them into a base score, then adds
penalty points for any active bottlenecks.

### Step 1: CPU utilization and I/O wait

The kernel exposes cumulative CPU jiffie counts in `/proc/stat`. The script reads
that file twice, separated by the sample interval, and computes the delta:

```
cpu_busy%  =  100 × (total_delta − idle_delta − iowait_delta) / total_delta
iowait%    =  100 × iowait_delta / total_delta
```

Separating iowait matters: a CPU blocked on disk shows up as "idle" in the busy
figure but is captured here as iowait, so no signal is lost.

### Step 2: Memory pressure

```
mem_used%  =  100 × (MemTotal − MemAvailable) / MemTotal
```

`MemAvailable` not `MemFree` is used because the kernel reclaims page cache
on demand. This avoids false pressure warnings on systems that aggressively cache
disk reads.

Swap usage is tracked separately for the bottleneck penalty in step 5.

### Step 3: Normalized load average

```
load%  =  (load_1m / cores) × 100
```

The 1-minute load average from `/proc/loadavg` is divided by the logical CPU core
count. A value of 100% means exactly one runnable task per core, fully committed
but not over-scheduled.

### Step 4: Base strain (weighted average)

The four signals are blended into a 0 to 100 base score:

| Signal              | Weight | Rationale                                             |
|---------------------|--------|-------------------------------------------------------|
| CPU busy %          | 40%    | Primary throughput indicator                          |
| Normalized load %   | 30%    | Scheduling demand, including disk/network wait states |
| Memory used %       | 20%    | Working-set pressure                                  |
| I/O wait %          | 10%    | Disk latency (partially reflected in load already)    |

```
base_strain  =  cpu×0.40  +  load×0.30  +  mem×0.20  +  iowait×0.10
```

On a perfectly idle system this approaches 0. On a system where every resource is
fully saturated with nothing queuing, it approaches 100.

### Step 5: Bottleneck penalties

When resources are over-committed, penalty points are added on top of the base
score, pushing `server_strain` above 100:

| Condition                    | Penalty formula          | What it signals                              |
|------------------------------|--------------------------|----------------------------------------------|
| Load average > core count    | `+(excess/cores) × 30`   | Tasks queuing for CPU, scheduler backlogged  |
| I/O wait > 20%               | `+(iowait − 20) / 2`     | Disk is a throughput bottleneck              |
| Swap used > 5%               | `+(swap_pct − 5) / 2`    | Physical RAM exhausted, actively paging      |

A strain of **120**, for example, means the system is not just fully utilized but
is actively building up queues and response times will be degrading.

---

## Dependencies

| Dependency       | Purpose                                      |
|------------------|----------------------------------------------|
| `bash`           | Shell interpreter                            |
| `awk`            | Field parsing and floating-point arithmetic  |
| `nproc`          | Core count (falls back to `/proc/cpuinfo`)   |
| `/proc/stat`     | CPU jiffie counters                          |
| `/proc/meminfo`  | Memory and swap figures                      |
| `/proc/loadavg`  | Load average                                 |

All dependencies are part of the Linux base system. No packages to install. Should work on any modern distro.
