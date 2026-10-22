# Unified goal evidence ledger

Date: 2026-10-22. Source: parent PRD R1-R12 and original attachment. This ledger
does not close a requirement from coordinator intent or historical test counts.
Every completion claim needs current owned files, command results and artifact
or installed-runtime evidence appropriate to that requirement.

## Cross-product ownership

| Product repo | Current owner/evidence source | Current acceptance status |
| --- | --- | --- |
| qfli_c (C/C++) | C w1R:p1; global sync record | Reported host baseline; OHOS and final scope open. |
| qfli_dart | Dart w1T:p1; global seq73/74/82 | Reported portable failures; OHOS open. |
| qfli_go | Go coordinator; global seq75/80 | Reported host120/120; OHOS open. |
| qfli_java | Java w28:p1; global seq119/120 | Peer reports current x64 OHOS280/1120 plus diagnostics/JDI; ARM64 independent. |
| qfli_lua | Lua coordinator; global sync | Owner identified; current evidence still required. |
| qfli_rust | Rust coordinator; global seq81 | Reported mixed host/runtime labels; OHOS open. |
| qfli_note | Note w2A:p1; global seq78 | Note-only work reported; OHOS open. |
| qfli_python | This task and four child plans | Fresh116/120 example host baseline; repairs/OHOS/final scope open. |
| qfli_web | Owner/evidence not yet verified here | Open, not silently excluded. |
| qfli_sql | Owner/evidence not yet verified here | Open, not silently excluded. |
| qfli_json | Owner/evidence not yet verified here | Open, not silently excluded. |
| qfli_studio_core | C sole common writer; ef345913/daddce2 | Peer reports712 pass/2skip; dependent Python acceptance remains open. |

qflistudio is the combined product, not a reason to enable online features in
standalone apps. Reported peer counts are pointers, not this task's verified
cross-product passes. The shared ledger/channel remains authoritative ownership
coordination; each product retains runtime/content verification responsibility.

## Requirement verification matrix

| Requirement | Required evidence | Current state |
| --- | --- | --- |
| R1 Trellis/cooperation | Approved plans, task status, explicit file ownership | Approved plan recorded; modules/tools active; ownership published77/84/124/133/137. |
| R2 all current content OHOS | Exhaustive per-unit results from final installed app, fixture round trip | Python defects established; all products' installed gates open. |
| R3 >100 new substantial examples | Baseline gate then authored delta/count, semantic review, full runtime reports | Python target+180/total300; no expansion yet. |
| R4 chips/title badges | Common source/widget checks and dependent product rendering | C-owned pending evidence. |
| R5 direct language tools | Actual root Tools interactions/layout and operation results | Python current extra menu; repair planned. |
| R6 unsaved diagnosis/underlines | Native analyzer snapshots/no side effects, range/revision tests, shared UI | C schema frozen; Python adapter planned. |
| R7 explorer/multi-root | Reopen/restart/multiple-root persistence and operation isolation tests | C adopted prior WIP and published daddce2; Python acceptance pending. |
| R8 debugging/panels | Genuine pause/step/continue/stop and session recovery, actual panel behavior | Python trace support exists upstream but disabled; child planned. |
| R9 highlighting/headers | Per-language renders and actual project import/compile/run | Shared/C ownership; current evidence required. |
| R10 Python modules/packages | Useful API execution, local install lifecycle/rollback, actual OHOS imports | Ten useful bundles; real host306 assertions+128 encoding+256 CSV;44 package tests; OHOS open. |
| R11 offline | Executed local-only flows, release manifest/package/config inspection | No network additions; existing OHOS INTERNET permission needs disposition. |
| R12 checks/commits/push | Fresh checks, staged diff review, commit IDs, verified remote OIDs | Current module batch157 whole-app tests passed; source/evidence commit in preparation. |

## Current blockers versus independent work

Target127.0.0.1:5555 is now live, superseding the original empty observation.
Web owns the current exclusive window; queue is Lua, SQL, Python when ready,
Rust. Python has not accepted a slot or mutated device state. Signed matching
audit builds and a released device window are still required for device proof.
Common API/source/fixture delivery is an integration dependency, not approval
to edit another owner's files. Review approval is the required planning phase
transition. Keep umbrella completion unproven until every row has evidence.
