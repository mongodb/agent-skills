---
name: mongodb-self-managed-audit
description: >
  Production readiness audit for self-managed MongoDB Enterprise Advanced
  (7.0, 8.0, 8.3, 9.0) on Linux hosts the user controls, scored against
  MongoDB production notes. Use when auditing a self-managed MongoDB host
  before or after installing MongoDB, or when the user asks about a single
  check area (THP, NUMA, ulimits, kernel tunables, WiredTiger cache, TCMalloc)
  on a self-managed Enterprise Advanced host. Do not use for MongoDB Atlas,
  Community Edition, non-Linux hosts, or general performance tuning.
metadata:
  version: 1.0.0
license: Apache-2.0
---

# Self-Managed Deployments Checks

Expected values come from the production notes, current release first:

- https://www.mongodb.com/docs/v9.0/administration/production-notes/ (9.0)
- https://www.mongodb.com/docs/manual/administration/production-notes/ (8.3)
- https://www.mongodb.com/docs/v8.0/administration/production-notes/ (8.0)

## Model

Run this audit on Sonnet. `scripts/run-all-checks.sh` already tallies the
statuses, so what the model contributes is judgment: choosing UNKNOWN over PASS
when a read fails, scoping container findings to the node, and matching a
remediation to the deployment. Haiku suits a single-script run where the user
wants the output read back.

The customer-facing document is a separate deliverable. Produce this audit, then
take the findings to `mongodb-ce-toolkit:mongodb-writeup`.

## Prerequisites

Resolve all four before the first check. Ask while any one is unresolved.

1. MongoDB version, 7.0, 8.0, 8.3 or 9.0. Ask once. Get the patch version too:
   the kernel rule below bands on it.
2. Shell access to the target host: local, SSH, or an open session.
3. Linux target. The scripts read `/proc`, `/sys`, and `sysctl`.
4. Privilege level: root, sudo, or unprivileged. Record it in the report.

Audit only the host the user named as the target.

## Workflow

1. Confirm the major version; capture distro and kernel.
2. Run the suite: `bash scripts/run-all-checks.sh --version 9.0 --dbpath /var/lib/mongo`
3. For every WARN and FAIL, read `references/checks-reference.md` for the expected
   value and the remediation.
4. Write the report using the Report section below.

The audit is done when every check carries PASS, WARN, FAIL, or UNKNOWN, and
every WARN and FAIL carries a remediation.

## Executing Checks

`scripts/run-all-checks.sh` runs every category and tallies the totals. Prefer it
over per-script runs.

- `--version` takes `7.0`, `8.0`, `8.3`, or `9.0`. Bare `7` and `8` are tolerated
  as 7.0 and 8.0. A patch version such as `8.0.4` is accepted and retained: the
  checks score against `8.0`, and the kernel rule uses the patch component.
- Any other value is a hard error: the run exits non-zero with a usage line
  rather than degrading silently.
- `--dbpath` overrides dbPath autodetection.
- Checks gated by version use a minimum version. The 8.0-and-later checks skip
  automatically when `--version` is 7.0.

Run a single script when the user asked about one area:

```bash
bash scripts/check-thp.sh --version 8.3
```

| Category | Script |
|---|---|
| OS & Platform | `scripts/check-platform.sh` |
| Kernel & System | `scripts/check-kernel.sh` |
| NUMA | `scripts/check-numa.sh` |
| Transparent Huge Pages | `scripts/check-thp.sh` |
| Filesystem & Storage | `scripts/check-storage.sh` |
| Network | `scripts/check-network.sh` |
| Ulimits | `scripts/check-ulimits.sh` |
| Clock Synchronization | `scripts/check-clock.sh` |
| MongoDB Process | `scripts/check-mongod.sh` |
| WiredTiger | `scripts/check-wiredtiger.sh` |
| Security | `scripts/check-security.sh` |
| TCMalloc (8.0 and later) | `scripts/check-tcmalloc.sh` |

The kernel verdict is the one rule here that is easy to get wrong and expensive
to get wrong, so it carries its own tests:

```bash
bash scripts/test-kernel-matrix.sh
```

Run it after any edit to `scripts/lib-version.sh`. It asserts the full
SERVER-125742 matrix, including the case the public docs contradict: on
8.0.21 through 8.0.29, kernel 7.0.14 is not a remedy. Exit 0 means every band
still scores correctly.

Every script emits one line per check:

```
[FAIL] thp-enabled: /sys/kernel/mm/transparent_hugepage/enabled is [always] madvise never, expected never
[WARN] vm-swappiness: vm.swappiness is 60, expected 1
[PASS] ulimit-nofile: open files limit is 64000
[UNKNOWN] vm.zone_reclaim_mode: not readable by this unprivileged run; re-run with sudo
```

## Status Vocabulary

| Status | Meaning | Action |
|---|---|---|
| PASS | Requirement met | None |
| WARN | Suboptimal; degrades under load | Remediate, non-blocking |
| FAIL | Requirement not met | Blocking; fix before production |
| UNKNOWN | Could not be read or verified | State why |
| INFO | Informational | None |

UNKNOWN is the single status for anything a run could not establish. It covers
an unreadable `/proc`, `/sys`, or sysctl path, including one an unprivileged run
cannot see; a script that exited non-zero; and a runtime value with no live
server to read it from. Carry the reason with it.

The scripts emit `[UNKNOWN]` themselves for failed reads, with the reason on the
line: whether the key is absent from the kernel, or the run lacked the privilege
to read it. Those are different remediations, so do not collapse them.
`run-all-checks.sh` tallies UNKNOWN alongside the other statuses and lists each
one with its reason, so the report's Unknown section comes from the run rather
than from reconstruction. A run with zero FAIL and zero WARN but a non-zero
UNKNOWN count is not a pass; the suite says so in its closing line.

A FAIL stays blocking even when the deployment already serves production traffic.

How to word a finding, which applies from the moment you triage it and not only
when you assemble the report: say a setting is "not compliant with MongoDB
documented performance guidance" rather than that MongoDB "requires" a value,
or that the host is a "hard blocker". Most of these are tunables with documented
recommended values, and a customer reading "required" reasonably infers mongod
will refuse to start. Two cases earn literal language because they are literally
true: a kernel inside the documented incompatibility range, where mongod crashes
on startup or refuses to start, and a missing or unwritable dbPath, where mongod
cannot start at all. A ulimit below threshold, a swappiness of 60, or THP set
the wrong way are all FAIL and all blocking for sign-off, and none of them stop
mongod from starting. Keep the PASS, WARN, FAIL and UNKNOWN labels exactly as
they are; this governs the prose around them.

## Runtime Values the Scripts Cannot Read

The scripts read the host, the `mongod` process table, and `mongod.conf`. They
open no database connection, so applied runtime state stays out of reach: the
effective values from `getParameter`, WiredTiger cache usage from
`serverStatus`, and replica set status.

Where those values matter, read them through the MongoDB MCP server, which holds
the credentials. Keep connection strings, usernames, and passwords out of script
arguments, environment variables, and the report. Where the MCP server is
unavailable, report the runtime values as UNKNOWN and keep the config-file
findings the scripts produced.

## Edge Cases

| Situation | Required behavior |
|---|---|
| `mongod` stopped, including a pre-install audit | The scripts fall back to `mongod.conf` and emit WARN on the process checks. Keep those config findings; mark only runtime values UNKNOWN. |
| Container or Kubernetes | THP, NUMA, and sysctl findings describe the node, not the pod. Say which apply to the node and which are settable from inside the container. |
| No shell access to the host | Ask the user to run `scripts/run-all-checks.sh` on the host and paste the output, then interpret that output. |
| Version unresolved after one ask | Run the checks common to 7.0, 8.0, 8.3 and 9.0, skip the 8.0-and-later checks, and flag the gap in the report. |

## Version Differences

- Transparent huge pages invert at 8.0. On MongoDB 8.0 and later, THP enabled
  (`always`, defrag `defer+madvise`, `khugepaged/max_ptes_none` 0,
  `vm.overcommit_memory` 1) is what MongoDB documents; THP disabled is not
  compliant with MongoDB documented performance guidance. On 7.0 and earlier
  the reverse holds and `never` is the documented value. Confirm the major
  version before reporting a THP status, because the documented value for one
  version is a FAIL on the other.
- The kernel restriction is keyed to the MongoDB maintenance release, not the
  major version, so resolve the patch version before scoring it. Source:
  SERVER-125742.
  - 7.0 is not affected on any kernel. Do not carry a kernel finding into a
    7.0 audit.
  - 8.0.0 through 8.0.20 on kernel 6.19 through 7.0.13: mongod starts, then
    crashes after roughly 60 seconds, with potential corruption. This is a
    data-loss risk, not an availability one. Kernel 7.0.14 or later clears it.
  - 8.0.21 through 8.0.29 and 8.3.0 through 8.3.8: mongod exits during startup
    on any kernel 6.19 or later, 7.0.14 included. A kernel upgrade is not a
    remedy here, which is the counterintuitive case; only a MongoDB upgrade
    clears it.
  - 8.0.30 and later, 8.3.9 and later, and 9.0: mongod exits during startup on
    6.19 through 7.0.13 only, and kernel 7.0.14 or later clears it.
  - A bare major.minor with no patch component cannot be placed in a band, so
    the scripts return the strictest verdict that band could carry. Report the
    assumption rather than inferring a fix you cannot see.
- No host-level tunable requirement differs between 8.0, 8.3 and 9.0. THP,
  `khugepaged/max_ptes_none`, `vm.overcommit_memory`, ulimits, readahead,
  `vm.swappiness` and `tcp_keepalive_time` are identical across the three, so
  8.3 and 9.0 inherit the 8.0-and-later expectations. Confirmed against the 9.0
  production notes, which restate `vm.swappiness` 1 or 0,
  `tcp_keepalive_time` 120, readahead 8 to 32, and the same WiredTiger cache
  formula. That page phrases the THP rule as "If you are running MongoDB 8.0,
  enable Transparent Hugepages", without naming 9.0; read it as 8.0 and later,
  since it is the 9.0 manual.
- ARM64 requires ARMv8.2-A minimum on 7.0 and later; ARMv8.4-A is usable.
- RHEL 8 on ppc64le and s390x use legacy TCMalloc even on 8.0 and later.
- Ubuntu 24.04 is supported on 8.0 and later, not on 7.0. The 9.0 production
  notes list platforms only as "Ubuntu LTS" and defer to the platform support
  matrix, so confirm a specific LTS there rather than from the notes page.

`references/checks-reference.md` carries every threshold and the full
version-specific detail.

## Report

Each FAIL and WARN line carries the observed value, the expected value, and the
remediation.

Redact as you write, not afterwards. Replace hostnames, connection strings, IP
addresses, org and project names and customer identifiers with a neutral label
in the report itself. A note such as "redact before sharing" left next to the
real value is not redaction: the report is the artifact that leaves the
engagement, and the value is still in it. If you need the real hostname to stay
traceable, use a stable label such as `db-node-01` and keep the mapping outside
the report.

```
## MongoDB Production Readiness Report
Date: <date>
Host: <neutral label, e.g. db-node-01. Never the real hostname.>
MongoDB Version: <7.0.x | 8.0.x | 8.3.x | 9.0.x | not installed>
OS: <distro + kernel>
Privilege level: <root | sudo | unprivileged>

### Summary
PASS: N  WARN: N  FAIL: N  UNKNOWN: N

### Failures (blocking, fix before production)
<check name>: <observed> vs <expected> - <remediation>

### Warnings (fix before heavy load)
<check name>: <observed> vs <expected> - <remediation>

### Unknown (not verified this run)
<check name>: <why it could not be read>

### All Checks
| Check | Status | Observed | Expected |
|---|---|---|---|
```
