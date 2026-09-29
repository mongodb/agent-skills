# Self-Managed Deployments Checks Reference

Sources:

- 9.0: https://www.mongodb.com/docs/v9.0/administration/production-notes/
- 8.3: https://www.mongodb.com/docs/manual/administration/production-notes/
- 8.0: https://www.mongodb.com/docs/v8.0/administration/production-notes/
- THP: https://www.mongodb.com/docs/manual/tutorial/transparent-huge-pages/

Version columns below mean the MongoDB major version, not the kernel or OS
version. Checked against the 8.3 and 9.0 production notes.

No host-level tunable requirement differs between 8.0, 8.3 and 9.0, so both
inherit the 8.0-and-later values and need no further column. The 9.0 notes
restate the same `vm.swappiness`, `tcp_keepalive_time`, readahead and
WiredTiger cache values. Add a column only if a divergence appears in a later
release.

One wording note on the 9.0 page: it states "If you are running MongoDB 8.0,
enable Transparent Hugepages. If you are running MongoDB 7.0 or earlier,
disable Transparent Hugepages", and does not name 9.0. Read that as 8.0 and
later, since it is the 9.0 manual.

## Platform & OS

| Check | 7.0 | 8.0 and later | Notes |
|---|---|---|---|
| Recommended platforms (x86_64) | Same | Same | Amazon Linux, Debian, RHEL, SLES, Ubuntu LTS, Windows Server |
| x86_64 minimum microarch | Same | Same | Intel Haswell or later Core; Intel Tiger Lake or later Celeron/Pentium; AMD Bulldozer or later |
| AVX | Required | Required | Required from 5.0 onward |
| ARM64 minimum microarch | ARMv8.2-A | ARMv8.2-A | 7.0 and later also support ARMv8.4-A or later |
| Kernel 6.19 through 7.0.13 | Not affected | FAIL | Affects 8.0 and later only, not 7.0. Severity and remedy depend on the maintenance release; see "Kernel restriction, by maintenance release". |
| Minimum kernel | 2.6.36 | 2.6.36 | XFS needs 2.6.25; ext4 needs 2.6.28; RHEL/CentOS needs 2.6.18-194 |
| Oracle Linux kernel | RHCK only | RHCK only | UEK is not supported |
| CPU cores | 2 real cores | 2 real cores | Per mongod or mongos instance |
| AES-NI | Recommended | Recommended | Material advantage for the encrypted storage engine (Enterprise) |
| Endianness | Little-endian | Little-endian | Server requires x86/x86_64 little-endian; client libraries accept either |

### Kernel restriction, by maintenance release

Source: SERVER-125742, issue status as of 2026-08-24, which carries the
authoritative compatibility matrix. Root cause: rseq behavior changes in the
Linux kernel broke the TCMalloc vendored in MongoDB. Kernel 7.0.14+ and 7.1.0+
restore the previous userspace behavior, and mongod's own startup guard was
narrowed to match in 8.0.30, 8.3.9 and 9.0.

The verdict depends on the MongoDB maintenance release, so resolve the patch
version before scoring. `scripts/lib-version.sh` implements this matrix in
`kernel_tcmalloc_status`.

| MongoDB | Kernel below 6.19 | Kernel 6.19 through 7.0.13 | Kernel 7.0.14+ / 7.1.0+ |
|---|---|---|---|
| 7.0, all versions | Supported | Supported | Supported |
| 8.0.0 - 8.0.20 | Supported | DO NOT USE: crashes after roughly 60s, potential corruption | Supported |
| 8.0.21 - 8.0.29 | Supported | Exits during startup | Exits during startup |
| 8.3.0 - 8.3.8 | Supported | Exits during startup | Exits during startup |
| 8.0.30+, 8.3.9+, 9.0 all versions | Supported | Exits during startup | Supported |

Three consequences that change a remediation:

- 7.0 is not affected on any kernel. Do not carry a kernel finding into a 7.0
  audit.
- On 8.0.21 through 8.0.29 and 8.3.0 through 8.3.8, upgrading the kernel is not
  a remedy. Those releases exit on any kernel 6.19 or later, 7.0.14 included.
  Only a MongoDB upgrade clears it.
- On 8.0.0 through 8.0.20 the failure is worse than a refusal to start: mongod
  runs, then crashes, with potential corruption. Treat it as a data-loss risk,
  not an availability one.

A distro kernel well below the range, such as RHEL 9.4 on
`5.14.0-427.13.1.el9_4`, sits outside every restriction above.

Version-string caveat: the guard compares the kernel version literally, so a
distro that backports the rseq fix without relabelling still reads as affected.
Ubuntu 26.04 ships `7.0.0-XX-generic`, which is numerically at or above 6.19 but
never at or above 7.0.14, so it stays blocked even once the fix is present
(SERVER-131155, SERVER-131779). Where a customer reports this, check the distro
kernel changelog rather than the `uname -r` string alone.

## Transparent Huge Pages

THP guidance inverts at 8.0. Confirm the major version before reporting a status.

| Setting | 7.0 and earlier | 8.0 and later |
|---|---|---|
| `/sys/kernel/mm/transparent_hugepage/enabled` | `never` | `always` |
| `/sys/kernel/mm/transparent_hugepage/defrag` | `never` | `defer+madvise` |
| `/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none` | N/A | `0` |
| `/proc/sys/vm/overcommit_memory` | N/A | `1` |
| Persistence | Any mechanism that survives reboot | Any mechanism that survives reboot |

On 8.0 and later, `enabled=never` is a FAIL. On 7.0 and earlier, `enabled=always`
is a FAIL. `madvise` is a WARN on both.

Persistence has no single required mechanism: a systemd unit ordered before
mongod, a tuned profile, or a value baked into the host build image all
qualify. What matters is that the setting survives a reboot, since a runtime
`echo` does not. On RHEL and derivatives tuned is usually already active and is
the path of least resistance, so check `tuned-adm active` before proposing a new
unit. A tuned profile that sets the wrong value for the deployment's version is
worse than none, because it silently reasserts it on every boot.

## Kernel & System

| Check | Expected | Status rule |
|---|---|---|
| `vm.swappiness` | 1 | 0 is also valid on a host dedicated to MongoDB with swap disabled. 2-10 WARN, above 10 FAIL. Distribution default of 60 is not recommended. |
| `vm.force_cgroup_v2_swappiness` | 1 on RHEL/CentOS | WARN if 0, so that `vm.swappiness` overrides the cgroup default |
| `vm.zone_reclaim_mode` | 0 | FAIL if non-zero |
| `vm.overcommit_memory` | 1 on 8.0 and later | WARN otherwise, set alongside THP. Evaluated inside `check-thp.sh`, not `check-kernel.sh`. |
| `vm.dirty_ratio` | 15 or lower | Above 40 WARN |
| `vm.dirty_background_ratio` | 3 to 5 | Above 10 WARN |
| `kernel.pid_max` | 64000 or more | Below 32768 WARN |
| `fs.file-max` | 98000 or more | Below 64000 WARN |
| Swap strategy | Either assign swap with `vm.swappiness=1`, or run without swap and `vm.swappiness=0` | Swapping is preferable to the OOM killer terminating mongod |

## NUMA

| Check | Expected | Status rule |
|---|---|---|
| NUMA in BIOS | Disabled where the platform allows | INFO |
| `vm.zone_reclaim_mode` | 0 | FAIL if non-zero on a NUMA system |
| mongod launched under `numactl --interleave=all` | Yes | FAIL when NUMA is present and interleaving is absent |
| `numad` daemon | Stopped | FAIL if running |
| Windows | Memory interleaving enabled in BIOS | INFO |

## Filesystem & Storage

| Check | Expected | Status rule |
|---|---|---|
| dbPath filesystem | XFS strongly recommended, ext4 acceptable | WARN for anything else |
| `fsync()` on directories | Supported | Required |
| NFS for dbPath | Acceptable with WiredTiger when POSIX.1 compliant | WARN, since performance degrades. Mount with `bg hard nolock noatime nointr`. |
| RAID level | RAID-10 | WARN on RAID-5 or RAID-6, which lack the performance |
| Readahead | 8 to 32 sectors | WARN outside that range. Higher favors sequential I/O while MongoDB is random. |
| I/O scheduler, virtual or cloud | `none` | `kyber` is acceptable where several workloads share the device (kernel 4.12+) |
| I/O scheduler, NVMe or SSD | `none` | WARN otherwise |
| I/O scheduler, spinning disk | `mq-deadline` | WARN otherwise |
| `atime` | Off on the volume holding data files | WARN if missing |
| AV and EDR exclusions | dbPath and logPath excluded | WARN when unconfirmed |
| dbPath permissions | mongod owns the path, read and write | FAIL otherwise |
| Storage engine files match configuration | Match | FAIL on mismatch; engine data files cannot be mixed |
| Component separation | Separate devices for data, journal, logs, indexes | INFO. Indexes via `storage.wiredTiger.engineConfig.directoryForIndexes`. |
| Media | SSD recommended where economical | INFO |

## Network

| Check | Expected | Status rule |
|---|---|---|
| `net.ipv4.tcp_keepalive_time` | 120 seconds | Above 120 WARN. 300 is the documented override ceiling; the 7200 default leaves stale connections. Applies to IPv4 and IPv6. |
| Windows `KeepAliveTime` | 120000 ms (0x1d4c0) | Default when absent is 7200000 ms; override ceiling is 600000 ms |
| `net.core.somaxconn` | 4096 or more | Below 128 WARN |
| `net.ipv4.tcp_max_syn_backlog` | 4096 or more | Below 512 WARN |
| `net.core.netdev_max_backlog` | 3000 or more | Below 1000 WARN |
| Hostname resolution | Resolves | FAIL when unresolvable, since replica sets depend on it |
| Connection pool sizing | 110 to 115 percent of typical concurrent requests | INFO. Tune via `maxIncomingConnections`; observe with `connPoolStats`. |
| HTTP interface | Off | FAIL if enabled in production |
| Network trust boundary | Access restricted to application servers, monitoring, and cluster members | WARN when listening broadly without a firewall |

## Clock Synchronization

| Check | Expected | Status rule |
|---|---|---|
| Time daemon | chronyd, ntpd, or systemd-timesyncd running | FAIL when absent. Required on all hosts, and critical in sharded clusters. |
| Clock synchronized | Yes | FAIL when the daemon reports unsynchronized |
| Tolerated drift | Within `maxAcceptableLogicalClockDriftSecs` | Drift of a year or more between components breaks communication |
| Timezone | Consistent across cluster members | INFO |

## Ulimits

| Check | Expected | Status rule |
|---|---|---|
| open files (`nofile`) | 64000 or more | mongod logs a startup warning below 64000. Below 1024 FAIL. |
| processes (`nproc`) | 64000 or more | Below 32768 FAIL |
| virtual memory (`as`) | unlimited | WARN if limited |
| max locked memory | unlimited | WARN if limited |
| core file size | unlimited for debugging | INFO |

## MongoDB Process

| Check | Expected | Status rule |
|---|---|---|
| mongod running | Yes | When stopped, the scripts fall back to config files; findings remain valid |
| mongod version | 7.0.x, 8.0.x or 8.3.x | FAIL on an end-of-life release |
| Authorization | `security.authorization` enabled | FAIL when disabled |
| `bind_ip` | Not `0.0.0.0` unless deliberate | WARN when listening on all interfaces |
| `storage.dbPath` | Contains only the configured engine's files | FAIL on mismatch |
| `logAppend` | true | WARN if false |
| `systemLog.destination` | file or syslog | WARN if absent |
| `operationProfiling.mode` | slowOp or all | INFO |
| `security.javascriptEnabled` | false where unused | FAIL when true under SELinux Enforcing, which segfaults mongod |
| TLS mode | requireTLS or allowTLS | WARN when disabled |

## WiredTiger

| Check | Expected | Status rule |
|---|---|---|
| Default cache size | `max(50% of (RAM - 1GB), 0.256GB)` | Bounded between 0.256 GB and 10000 GB |
| `cacheSizeGB` / `cacheSizePct` | Exactly one of the two | FAIL when both are set |
| `cacheSizePct` ceiling | 80 percent of available memory | FAIL above 80 |
| Container memory limit | Cache below the container limit | WARN when a cgroup limit sits below host RAM. `hostInfo` reports `system.memLimitMB`. |
| Multiple instances per host | `(50% of (RAM - 1GB)) / instance count` | WARN when unadjusted |
| Block compressor | snappy default; zstd for best ratio at lower CPU than zlib | INFO |
| Index prefix compression | On by default | INFO |
| Journaling | Enabled | FAIL when disabled |
| Concurrency | Throughput rises with concurrency up to the CPU count, then falls | INFO. Observe `ar` and `aw` in mongostat. |
| Cache statistics | `db.serverStatus().wiredTiger.cache` | INFO. Watch the eviction rate. |

## TCMalloc (8.0 and later, including 8.3 and 9.0)

| Check | Expected | Status rule |
|---|---|---|
| Kernel 6.19 through 7.0.13 | Avoided | FAIL on 8.0 and later. 8.0.0-8.0.20 risk corruption; 8.0.21-8.0.29 and 8.3.0-8.3.8 also fail on 7.0.14+. See "Kernel restriction, by maintenance release". |
| `MALLOC_CONF` | Unset, or deliberately correct | WARN when an override is present |
| RHEL 8 on ppc64le and s390x | Legacy TCMalloc | INFO. Expected on those platforms. |
| `tcmalloc.aggressive_memory_decommit` | Tuned for the workload | INFO |

## Security

| Check | Expected | Status rule |
|---|---|---|
| SELinux and AppArmor | Enforcing recommended | Configure explicitly only when dbPath, logPath, or the port differ from packaged defaults |
| Server-side JavaScript under SELinux | Disabled | FAIL when enabled under Enforcing, which causes segfaults |
| mongod process owner | Not root | FAIL when running as root |
| Keyfile or x.509 for replication | Configured | FAIL when a replica set has no internal auth |
| Audit logging (Enterprise) | Configured | WARN when absent |
| FIPS mode | Enabled where required | INFO |

## Virtual and Cloud Environments

| Platform | Guidance |
|---|---|
| AWS EC2 | Enable Enhanced Networking where the instance type supports it. Set `tcp_keepalive_time=120`. For reproducible performance use provisioned IOPS over ephemeral storage, disable DVFS and CPU power saving, disable hyperthreading, and bind memory locality with `numactl`. |
| Azure | Premium Storage outperforms Standard Storage. |
| VMware and KVM | Reserve the full memory allocation so the balloon driver cannot expand. Keep balloon and overcommit features in place rather than disabling them. On VMware, set affinity rules pinning VMs to specific ESX/ESXi hosts. To migrate a primary by hand, run `rs.stepDown()` then `db.shutdownServer()`. |

## Monitoring Tools

| Tool | Use |
|---|---|
| `iostat -xmt 1` | `%util` for device saturation; `avgrq-sz` for request size, where smaller means more random I/O |
| `bwm-ng` | Network bandwidth, for diagnosing network bottlenecks |
| `mongostat` | `ar` and `aw` columns for active reads and writes against the CPU count |
