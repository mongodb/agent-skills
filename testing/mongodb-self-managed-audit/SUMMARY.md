# mongodb-self-managed-audit: Eval Suite

This document explains what the evals in `evals/evals.json` test and why. The skill
audits self-managed MongoDB 7.0, 8.0, 8.3 and 9.0 Enterprise Advanced on Linux against
the production notes. The evals focus on the places where a model without the skill
tends to go wrong: version-dependent guidance, the kernel 6.19 TCMalloc startup guard,
and telling apart findings that are real, not applicable, or unknown.

## Layout

```
evals/
  evals.json    16 eval cases (prompt, fixture files, expected_output, expectations)
  assets/       host check output and config fixtures attached to the prompts
```

Each case attaches one fixture from `assets/`. Most fixtures are output from the
skill's `scripts/run-all-checks.sh`. Evals 3, 4 and 13 use raw command output instead
(`uname`, `rpm`, `systemctl`, `grubby`, `mongod.log`, `mongod.conf`, `free`, cgroup
limits, `getenforce`). Evals 14 to 16 are real output of the scripts, generated in
Rocky 9 and Ubuntu 24.04 containers with the kernel string, SELinux mode and mongod
binary faked; eval 14 deliberately shows the pre-fix `check-security.sh`, and evals
15 and 16 show the fixed scripts. Grading is done per assertion against the
`expectations` list.

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
| 13 | 8025-kernel-6192-roll-forward-not-a-fix | 8.0.25, Rocky 9 arm64, kernel 6.19.2 | Reviewer case. The team plans to roll forward to 7.0.14, which does not help 8.0.21 to 8.0.29. The working remedies are a kernel below 6.19 (the old 5.14 kernel is still installed), or a MongoDB upgrade paired with kernel 7.0.14+, since 8.0.30 on 6.19.2 still exits. Not the corruption band. | 6 |
| 14 | selinux-js-omitted-nested-tls-old-script | 8.0.30, Rocky 9, SELinux Enforcing | Reviewer case. An old audit run flagged TLS as missing (the config nests `net.tls.mode: requireTLS`) and passed JavaScript under Enforcing (`javascriptEnabled` is unset, so it defaults to true). Model must close the TLS item and overturn the JavaScript PASS. | 6 |
| 15 | 70-ubuntu2404-root-run-dbpath | 7.0.21, Ubuntu 24.04 arm64, run as root | Reviewer case. The user thinks the dbPath FAIL is wrong because root can write the directory. The check tests the `mongodb` service user; the restore left `root:root 750`. Also, 7.0 is not supported on Ubuntu 24.04 despite LTS. | 6 |
| 16 | 8025-run-as-8030-unprivileged-incomplete | 8.0.25 installed, run as `--version 8.0.30`, Rocky 9 arm64, kernel 7.0.14, unprivileged | Reviewer case. The kernel PASS was scored against the wrong patch; 8.0.25 will not start on 7.0.14. The config was unreadable (UNKNOWN, not PASS) and the Network category did not run (exit 127). Do not start mongod or close the window. | 8 |

Total: 16 cases, 104 assertions.

## Results

Latest run: 2026-11-18, on the skill with the PR #70 review fixes applied (nine
reviewer comments: kernel remedy, JavaScript default under SELinux, nested TLS,
dbPath access as the service user, failed reads as UNKNOWN, OS support matrix,
incomplete categories, patch-level version match, `labelText`). All 16 cases were
answered once with the skill and once without it.

| # | Case | With skill | Without skill | Delta |
| --- | --- | --- | --- | --- |
| 1 | thp-inversion-80-never-is-fail | 7/7 | 6/7 | +1 |
| 2 | thp-inversion-70-never-is-pass | 5/5 | 3/5 | +2 |
| 3 | kernel-7014-not-a-remedy-on-8025 | 6/6 | 3/6 | +3 |
| 4 | wiredtiger-cache-both-set-and-selinux-js | 3/4 | 1/4 | +2 |
| 5 | 90-inherits-80-expectations | 4/4 | 3/4 | +1 |
| 6 | container-node-scoping-unknown | 4/5 | 5/5 | -1 |
| 7 | broad-coverage-all-categories | 9/11 | 5/11 | +4 |
| 8 | amazonlinux-thp-madvise-selinux-permissive | 8/10 | 6/10 | +2 |
| 9 | 60-out-of-scope-rescored-as-70 | 4/8 | 7/8 | -3 |
| 10 | 70-host-built-from-80-golden-image | 8/8 | 7/8 | +1 |
| 11 | 80-ppc64le-thp-always | 5/5 | 2/5 | +3 |
| 12 | 8034-ubuntu-kernel-labelled-700 | 5/5 | 4/5 | +1 |
| 13 | 8025-kernel-6192-roll-forward-not-a-fix | 5/6 | 4/6 | +1 |
| 14 | selinux-js-omitted-nested-tls-old-script | 6/6 | 5/6 | +1 |
| 15 | 70-ubuntu2404-root-run-dbpath | 6/6 | 5/6 | +1 |
| 16 | 8025-run-as-8030-unprivileged-incomplete | 8/8 | 5/8 | +3 |
| | Total | 93/104 (89%) | 71/104 (68%) | +22 |

Leaving out eval 6, which does not discriminate (see the design notes), the scores
are 89/99 with the skill and 66/99 without. The four new reviewer cases (13 to 16)
score 25/26 with the skill and 19/26 without.

### Run history

| Run | Skill version | Cases | With skill | Without skill | Delta |
| --- | --- | --- | --- | --- | --- |
| 2026-10-22 | just before `c64ba13` | 12 | 75/78 | not run | n/a |
| 2026-11-13 | `c64ba13` | 12 | 72/78 | 47/78 | +25 |
| 2026-11-18 | PR #70 review fixes | 16 | 93/104 | 71/104 | +22 |
| 2026-11-18, evals 1 to 12 only | PR #70 review fixes | 12 | 68/78 | 52/78 | +16 |

The 2026-10-22 run re-answered only cases 5 and 7 after a fix, so it mixes two skill
versions. On the same 12 cases the delta moved from +25 to +16 between 2026-11-13 and
2026-11-18. The skill text those cases depend on did not change, so most of that
movement is run-to-run variance in a single sample per arm, in both the answers and
the grading.

### Method

- A separate Sonnet 5.5 agent answered each case. It saw the prompt and the attached
  fixture, and nothing else from `testing/`. It had no shell on the target host and
  no web or internal search.
- With the skill, the agent read `SKILL.md` and followed it, opening references and
  scripts as the skill directs. It did not run the scripts.
- Without the skill, the agent answered from its own knowledge. It could not read any
  skill file or use the Skill tool. Each agent's tool calls were checked afterwards:
  no baseline agent opened a skill file, and no agent in either arm opened the answer
  key.
- An Opus 5.5 grader scored every assertion PASS or FAIL against `expectations`, using
  `expected_output` for intent and the fixture when an assertion depends on the
  evidence. Partial, implied or hedged coverage is a FAIL. A "Does not ..." assertion
  passes only if the answer avoids the behaviour entirely.
- Each arm had its own grader with the same instructions. The answer folders were
  labelled A and B, so neither grader knew which arm it was scoring.

### Reading the numbers

- Without the skill, answers miss the version-specific facts: the kernel 6.19 guard
  and its remedy (evals 3, 13 and 16), THP on ppc64le (eval 11), the `cacheSizePct`
  percentage reading and the JavaScript segfault under SELinux (evals 4, 8 and 14),
  and full-category coverage (eval 7). In eval 16 the baseline would not say whether
  8.0.25 starts on kernel 7.0.14.
- With-skill failures in this run: eval 4 still lists `cacheSizePct` as its own FAIL.
  Eval 6 does not say which settings can be changed from inside the container. Eval 7
  misses that the absent dbPath is expected before install, and that NUMA does not
  apply on a single node. Eval 8 misses madvise as the middle state and the
  already-unlimited nproc. Eval 9 offers a risk-acceptance path, gives no
  one-major-at-a-time upgrade path, does not point to the lifecycle page, and shows a
  per-area scorecard. Eval 13 says "only a MongoDB upgrade clears it" before pairing
  the upgrade with kernel 7.0.14.
- Eval 9 is the one case where the baseline scored higher. Across the three runs the
  with-skill answer has missed the one-major-at-a-time upgrade path every time, which
  points at the 6.0 stop rule in `SKILL.md`: it says to upgrade to a covered release,
  but not one major at a time, and it does not rule out a risk-acceptance path.
- One eval 12 assertion ("Does not quote internal Slack or ticket discussion; cites
  SERVER-125742 and SERVER-131779 only") can be read two ways. On 2026-11-13 the
  grader failed the baseline on it for citing neither ticket; on 2026-11-18 it passed
  the same behaviour. Splitting it into two assertions would remove the ambiguity.
- In two answers the skill was correct where the key is silent: eval 5 flags that the
  support matrix lists Ubuntu 26.04 only from 9.0.4, and eval 11 notes that RHEL 9 on
  ppc64le is listed only from 8.0.7. Neither was scored against the answer.

## Coverage by theme

| Theme | Cases |
| --- | --- |
| THP guidance flip at 8.0 (`never` before 8.0, `always` from 8.0) | 1, 2, 5, 8, 10 |
| THP disabled on legacy-TCMalloc architectures (ppc64le, s390x) | 11 |
| Kernel 6.19 TCMalloc startup guard and which releases carry the narrowed version | 1, 2, 3, 5, 7, 8, 12, 13, 16 |
| Ubuntu `7.0.0-NNN` kernel label and the 8.0.35 / 8.3.14 fix | 12 |
| WiredTiger cache sizing (mutually exclusive settings, ceiling, above-default, cgroup limit) | 4, 8 |
| SELinux and server-side JavaScript (including the `javascriptEnabled` default) | 4, 8, 14, 16 |
| TLS mode read from the nested `net.tls` key | 14 |
| dbPath access as the service user, not the auditing user | 15, 16 |
| Version-specific OS support matrix | 15 |
| Installed version vs `--version`, patch included | 10, 16 |
| UNKNOWN vs WARN vs not applicable (failed reads, incomplete categories) | 4, 6, 7, 16 |
| Overruling earlier script output that is wrong | 1, 10, 14 |
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
  arms scored 5/5 in iteration 1, and in the 2026-11-13 and 2026-11-18 runs the
  baseline scored 5/5 and the skill 4/5. It stays because it is the only test of the container edge case.
  Discount it when reading the delta.
- The fixtures for evals 7 and 8 are real output from live hosts, redacted only for
  hostnames and NIC names. They cover distro paths that the synthetic fixtures do not.
- Evals 13 to 16 come from the PR #70 review: each one reproduces a reviewer-reported
  script defect as a user scenario, so the model has to reach the right answer
  whether the script output is right (15, 16) or wrong (14), or absent (13).
- Two older fixtures sit on platforms the Enterprise support matrix does not list for
  their release: eval 5 runs 9.0.1 on Ubuntu 26.04 (listed from 9.0.4), and eval 11
  runs 8.0.4 on RHEL 9 ppc64le (listed from 8.0.7). No assertion covers either; an
  answer that flags them is correct.
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
