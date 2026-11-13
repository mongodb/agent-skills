# mongodb-self-managed-audit: Eval Suite

This document explains what the evals in `evals/evals.json` test and why. The skill
audits self-managed MongoDB 7.0, 8.0, 8.3 and 9.0 Enterprise Advanced on Linux against
the production notes. The evals focus on the places where a model without the skill
tends to go wrong: version-dependent guidance, the kernel 6.19 TCMalloc startup guard,
and telling apart findings that are real, not applicable, or unknown.

## Layout

```
evals/
  evals.json    12 eval cases (prompt, fixture files, expected_output, expectations)
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
| 4 | wiredtiger-cache-both-set-and-selinux-js | 8.3.4, mongod stopped | Config review. `cacheSizeGB` and `cacheSizePct` both set (FAIL), `cacheSizePct` 0.85 read as 0.85 percent (not above the 80 percent ceiling), `cacheSizeGB` 48 above the default, `javascriptEnabled` under SELinux Enforcing (segfault). Runtime values must be UNKNOWN, config findings still valid. | 4 |
| 5 | 90-inherits-80-expectations | 9.0.1, Ubuntu 26.04, kernel 7.0.0-38-generic (upstream 7.0.14) | 9.0 inherits the 8.0+ THP expectations, so the team's disable-THP runbook is outdated. 9.0 has the narrowed guard, so kernel 7.0.14 is not exposed. | 4 |
| 6 | container-node-scoping-unknown | 8.3, inside a Kubernetes pod | Unreadable `/sys` and `/proc` values are UNKNOWN, not WARN. THP, swappiness and zone_reclaim_mode belong to the worker node. Only `bind_ip 0.0.0.0` is actionable from this run. | 5 |
| 7 | broad-coverage-all-categories | 8.0.25, Ubuntu 24.04 on Azure, pre-install, unprivileged | Full prioritised remediation list across ulimits, network, kernel, THP, storage, clock, NUMA and security. Absent mongod is expected before install. Kernel 6.17 is below 6.19. | 11 |
| 8 | amazonlinux-thp-madvise-selinux-permissive | 8.0.25, Amazon Linux 2023 EC2, pre-install | THP `madvise` is WARN on 8.0+, SELinux Permissive is a non-blocking WARN, and 0.8 GB RAM is the real problem because the WiredTiger cache falls to the 0.256 GB floor. Kernel 6.18.48 is one minor version below the boundary. | 10 |
| 9 | 60-out-of-scope-rescored-as-70 | 6.0.19, RHEL 8.10, run forced to `--version 7.0` | Prerequisite stop rule. 6.0 is not a covered version, so the forced 7.0 run is not evidence of readiness. Model must refuse sign-off, cite the 6.0 end of life, require the upgrade before go-live, describe the one-major-at-a-time path through 7.0, and offer a re-audit afterwards. | 8 |
| 10 | 70-host-built-from-80-golden-image | 7.0.21, RHEL 9.4, run with `--version 8.0` | Inverse of eval 1. A golden image tuned for 8.0 passes an 8.0-scored run, but on 7.0 THP `always` and defrag `defer+madvise` are FAILs, `max_ptes_none` and `overcommit_memory` do not apply, and the tuned profile reasserts the wrong values on boot. The version-mismatch WARN invalidates the run. | 8 |
| 11 | 80-ppc64le-thp-always | 8.0.4, RHEL 9, ppc64le | THP on ppc64le and s390x. The legacy TCMalloc applies at every version and THP is expected disabled, so `always` is a FAIL even where the x86_64 rule passes it. | 5 |
| 12 | 8034-ubuntu-kernel-labelled-700 | 8.0.34, Ubuntu 24.04, kernel 7.0.0-1011-gcp | Ubuntu labels the fixed kernel 7.0.0. 8.0.30 to 8.0.34 still exit; the fix is 8.0.35 or 8.3.14. No release date stated. | 5 |

Total: 12 cases, 78 assertions.

## Results

Run on 2026-11-13 against the skill at commit `c64ba13`. Each case was answered once
with the skill and once without it.

| # | Case | With skill | Without skill | Delta |
| --- | --- | --- | --- | --- |
| 1 | thp-inversion-80-never-is-fail | 7/7 | 6/7 | +1 |
| 2 | thp-inversion-70-never-is-pass | 4/5 | 3/5 | +1 |
| 3 | kernel-7014-not-a-remedy-on-8025 | 6/6 | 2/6 | +4 |
| 4 | wiredtiger-cache-both-set-and-selinux-js | 4/4 | 1/4 | +3 |
| 5 | 90-inherits-80-expectations | 4/4 | 3/4 | +1 |
| 6 | container-node-scoping-unknown | 4/5 | 5/5 | -1 |
| 7 | broad-coverage-all-categories | 11/11 | 5/11 | +6 |
| 8 | amazonlinux-thp-madvise-selinux-permissive | 8/10 | 7/10 | +1 |
| 9 | 60-out-of-scope-rescored-as-70 | 6/8 | 6/8 | 0 |
| 10 | 70-host-built-from-80-golden-image | 8/8 | 6/8 | +2 |
| 11 | 80-ppc64le-thp-always | 5/5 | 0/5 | +5 |
| 12 | 8034-ubuntu-kernel-labelled-700 | 5/5 | 3/5 | +2 |
| | Total | 72/78 (92%) | 47/78 (60%) | +25 |

Leaving out eval 6, which does not discriminate (see the design notes), the scores
are 68/73 with the skill and 42/73 without.

### Method

- A separate Sonnet 5.5 agent answered each case. It saw the prompt and the attached
  fixture, and nothing else from `testing/`. It had no shell on the target host and
  no web or internal search.
- With the skill, the agent read `SKILL.md` and followed it, opening references and
  scripts as the skill directs. It did not run the scripts.
- Without the skill, the agent answered from its own knowledge. It could not read any
  skill file or use the Skill tool.
- An Opus 5.5 grader scored every assertion PASS or FAIL against `expectations`, using
  `expected_output` for intent and the fixture when an assertion depends on the
  evidence. Partial, implied or hedged coverage is a FAIL. A "Does not ..." assertion
  passes only if the answer avoids the behaviour entirely.
- Each arm had its own grader with the same instructions. The answer folders were
  labelled A and B, so neither grader knew which arm it was scoring.

### Reading the numbers

- The largest gaps are on version-specific facts: the kernel 6.19 guard (evals 3 and
  12), THP on ppc64le (eval 11, 0/5 without the skill), `cacheSizePct` read as a
  percentage (eval 4), and full-category coverage (eval 7).
- With-skill failures in this run: eval 2 does not say that `max_ptes_none` and
  `overcommit_memory` are not applicable on 7.0. Eval 6 hedges on `bind_ip`. Eval 8
  misses madvise as the middle state, and does not make `javascriptEnabled` a check
  before moving to Enforcing. Eval 9 hedges the 6.0 end-of-life date and gives no
  one-major-at-a-time upgrade path.
- One run per arm, so expect a few points of noise. A with-skill-only run on
  2026-10-22, just before `c64ba13`, scored 75/78 and failed on different cases. Only
  eval 2 and the eval 9 upgrade path failed both times.
- One eval 12 assertion ("Does not quote internal Slack or ticket discussion; cites
  SERVER-125742 and SERVER-131779 only") can be read two ways. The grader failed the
  baseline on it because the answer cited neither ticket. Read as a ban on internal
  quotes only, the baseline scores 48/78 and the delta is +24.

## Coverage by theme

| Theme | Cases |
| --- | --- |
| THP guidance flip at 8.0 (`never` before 8.0, `always` from 8.0) | 1, 2, 5, 8, 10 |
| THP disabled on legacy-TCMalloc architectures (ppc64le, s390x) | 11 |
| Kernel 6.19 TCMalloc startup guard and which releases carry the narrowed version | 1, 2, 3, 5, 7, 8, 12 |
| Ubuntu `7.0.0-NNN` kernel label and the 8.0.35 / 8.3.14 fix | 12 |
| WiredTiger cache sizing (mutually exclusive settings, ceiling, above-default, cgroup limit) | 4, 8 |
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
- Eval 6 is a coverage case restored from iteration 1. It does not discriminate: both
  arms scored 5/5 in iteration 1, and in the 2026-11-13 run the baseline scored 5/5
  and the skill 4/5. It stays because it is the only test of the container edge case.
  Discount it when reading the delta.
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
fixtures. To compare with the results above, set up the run as described under
Method: one answer agent per case and arm, and a separate strict grader per arm.
