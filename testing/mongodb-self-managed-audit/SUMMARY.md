# mongodb-self-managed-audit: Eval Suite

This document explains what the evals in `evals/evals.json` test and why. The skill
audits self-managed MongoDB 7.0, 8.0, 8.3 and 9.0 Enterprise Advanced on Linux against
the production notes. The evals focus on the places where a model without the skill
tends to go wrong: version-dependent guidance, the kernel 6.19 TCMalloc startup guard,
and telling apart findings that are real, not applicable, or unknown.

## Layout

```
evals/
  evals.json    10 eval cases (prompt, fixture files, expected_output, expectations)
  assets/       host check output and config fixtures attached to the prompts
```

Each case attaches one fixture from `assets/`. Most fixtures are output from the
skill's `scripts/run-all-checks.sh`. Evals 3 and 4 use raw command output instead
(`uname`, `rpm`, `systemctl`, `mongod.log`, `mongod.conf`, `free`, cgroup limits,
`getenforce`). Grading is done per assertion against the `expectations` list.

## Cases

| # | Name | Version / platform | What it tests | Assertions |
| --- | --- | --- | --- | --- |
| 1 | thp-inversion-80-never-is-fail | 8.0.4, RHEL 9 | Script output says THP `never` is PASS, but on 8.0+ the documented value is `always`. Model must overrule the pasted PASS, name the companion values (`defer+madvise`, `max_ptes_none=0`, `overcommit_memory=1`), give a persistent remediation, and reason about why kernel 5.14 is outside the restriction. | 7 |
| 2 | thp-inversion-70-never-is-pass | 7.0.14, RHEL 9 | The inverse case. THP `never` is correct on 7.0. Model must not apply 8.0+ guidance and must treat `max_ptes_none` and `overcommit_memory` as not applicable. | 5 |
| 3 | kernel-7014-not-a-remedy-on-8025 | 8.0.25, Rocky 9, kernel 7.0.14 | Production-down scenario. 8.0.21 to 8.0.29 and 8.3.0 to 8.3.8 exit on any kernel 6.19 or later. The fix is to upgrade MongoDB to 8.0.30+, not to reimage the host or downgrade the kernel. Log id 12257600 is a deliberate guard. | 6 |
| 4 | wiredtiger-cache-both-set-and-selinux-js | 8.3.4, mongod stopped | Config review. `cacheSizeGB` and `cacheSizePct` both set (FAIL), `cacheSizePct` 0.85 above the 80 percent ceiling, `javascriptEnabled` under SELinux Enforcing (segfault). Runtime values must be UNKNOWN, config findings still valid. | 4 |
| 5 | 90-inherits-80-expectations | 9.0.1, Ubuntu 26.04, kernel 7.0.14 | 9.0 inherits the 8.0+ THP expectations, so the team's disable-THP runbook is outdated. 9.0 has the narrowed guard, so kernel 7.0.14 is not exposed. | 4 |
| 6 | container-node-scoping-unknown | 8.3, inside a Kubernetes pod | Unreadable `/sys` and `/proc` values are UNKNOWN, not WARN. THP, swappiness and zone_reclaim_mode belong to the worker node. Only `bind_ip 0.0.0.0` is actionable from this run. | 5 |
| 7 | broad-coverage-all-categories | 8.0.25, Ubuntu 24.04 on Azure, pre-install, unprivileged | Full prioritised remediation list across ulimits, network, kernel, THP, storage, clock, NUMA and security. Absent mongod is expected before install. Kernel 6.17 is below 6.19. | 11 |
| 8 | amazonlinux-thp-madvise-selinux-permissive | 8.0.25, Amazon Linux 2023 EC2, pre-install | THP `madvise` is WARN on 8.0+, SELinux Permissive is a non-blocking WARN, and 0.8 GB RAM is the real problem because the WiredTiger cache falls to the 0.256 GB floor. Kernel 6.18.48 is one minor version below the boundary. | 10 |
| 9 | 60-out-of-scope-rescored-as-70 | 6.0.19, RHEL 8.10, run forced to `--version 7.0` | Prerequisite stop rule. 6.0 is not a covered version, so the forced 7.0 run is not evidence of readiness. Model must refuse sign-off, cite the 6.0 end of life, require the upgrade before go-live, describe the one-major-at-a-time path through 7.0, and offer a re-audit afterwards. | 8 |
| 10 | 70-host-built-from-80-golden-image | 7.0.21, RHEL 9.4, run with `--version 8.0` | Inverse of eval 1. A golden image tuned for 8.0 passes an 8.0-scored run, but on 7.0 THP `always` and defrag `defer+madvise` are FAILs, `max_ptes_none` and `overcommit_memory` do not apply, and the tuned profile reasserts the wrong values on boot. The version-mismatch WARN invalidates the run. | 8 |

Total: 10 cases, 68 assertions.

## Coverage by theme

| Theme | Cases |
| --- | --- |
| THP guidance flip at 8.0 (`never` before 8.0, `always` from 8.0) | 1, 2, 5, 8, 10 |
| Kernel 6.19 TCMalloc startup guard and which releases carry the narrowed version | 1, 2, 3, 5, 7, 8 |
| WiredTiger cache sizing (mutually exclusive settings, ceiling, floor, cgroup limit) | 4, 8 |
| SELinux and server-side JavaScript | 4, 8 |
| UNKNOWN vs WARN vs not applicable | 4, 6, 7 |
| Container and Kubernetes scoping | 6 |
| Version prerequisites (unsupported version, `--version` mismatch with the installed binary) | 9, 10 |
| Full-category sweep (ulimits, network, kernel, storage, clock, NUMA) | 7, 8 |

## Design notes

- Several prompts contain a plausible wrong premise from the user (a PASS from an
  outdated script run, an old runbook, "the kernel upgrade fixes it", "file all eight
  warnings"). Assertions check that the model corrects the premise instead of going
  along with it.
- Assertions that require a reason (evals 1, 3) reject answers that reach the right
  verdict for the wrong reason. For example, "do not reimage" only passes if the model
  blames the MongoDB release rather than the kernel.
- Eval 6 is a coverage case restored from iteration 1. Both with-skill and baseline
  scored 5/5 there, so it is not expected to discriminate. It stays because it is the
  only test of the container edge case. Discount it when reading the delta.
- The fixtures for evals 7 and 8 are real output from live hosts, redacted only for
  hostnames and NIC names. They cover distro paths that the synthetic fixtures do not.
- `assets/host-output-kernel-619.txt` is not referenced by any case in `evals.json`.

## Reproducing

```
/skill-creator Please run the evals for mongodb-self-managed-audit.
Evals are at testing/mongodb-self-managed-audit/evals/evals.json and
the skill is at skills/mongodb-self-managed-audit/. Run each eval
with_skill and without_skill.
```

No MongoDB MCP server or live cluster is needed. Every case runs from the attached
fixtures.
