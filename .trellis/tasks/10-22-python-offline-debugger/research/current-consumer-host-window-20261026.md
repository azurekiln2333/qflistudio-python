# Current Python consumer host window preparation

Status: source-ready for queue review. No execution grant and no host process.
READY704 was retired by global732 before ACK or execution.

The current freeze is `build/python-consumer-host-prepared-20261026/inputs.json`.
It records103 product inputs,200 shared-core inputs, the exact seven suite and
runner identities, and current published core HEAD64f0aa75a773c632a1101ce16e1900615b274960.
Shared live WIP is included. This is not tested-common-terminal acceptance.
External Pub-cache contents, SDK internals, transitive Trellis dependencies and
shared-core test-only files are outside this source inventory.

Independent source reviews resolved the three Home Tools fixture findings and
the default-off boundConsumers report defect. The final14 inner/28 outer
synthetic checks use doubles only. Exact final runner identities and log hashes
are recorded in `host-consumer-synthetic-verification-20261026.json`.
Real controls, all seven suites and scoped analysis remain unrun.

Before ACK, root must read the actual new grant, compare the current files with
the saved freeze, observe current memory and reject stale source or inadequate
capacity. A point memory sample is not a capacity guarantee. Never replay704.
The process observer retains the C717 coordination-only design and adds only the
fixed consumer-suite flag. The final sender terminal/result must be observed
before the next SDK grant. C must issue a fresh named execution grant.

## Proposed command after a fresh named grant

```powershell
python -B .trellis/tasks/10-22-python-offline-debugger/research/fixtures/run_python_granted_window.py `
  --grant <FRESH-NAMED-GRANT> `
  --next-owner c-coordinator `
  --output build/<FRESH-NAMED-GRANT>-window `
  --total-seconds 180 --ack-seconds 12 `
  --inner-seconds 138 --inner-plan-seconds 123 `
  --child-cleanup-seconds 5 --outer-cleanup-seconds 10 `
  --publish-seconds 15 --margin-seconds 5 --max-inner-phases 3 `
  --control-seconds 60 --min-phase-seconds 5 `
  --include-named-workspace --include-consumer-tests `
  --scope tool/python_debugger_ohos_audit.dart `
  --scope test/python_debugger_audit_test.dart `
  --scope test/python_tools_page_test.dart `
  --scope test/python_highlighting_test.dart `
  --scope lib/python_tools_page.dart `
  --flutter "D:\ProgramFiles\flutter_ohos\bin\flutter.bat" `
  --dart "D:\ProgramFiles\flutter_ohos\bin\dart.bat" `
  --node "D:\ProgramFiles\nodejs\node.exe" `
  --trellis-entry "D:\AppData\Roaming\npm\node_modules\@mindfoldhq\trellis\bin\trellis.js" `
  --channel qfli-core-release-sync --sender python-offline-1022
```

Reserved total:12+138+10+15+5=180 seconds. Child reservation:
123+3x5=138 seconds. The work budget is118 seconds. Controls are capped
at60 seconds; their actual duration is unmeasured. The seven suites and scoped
analysis share the remaining budget. Capacity is unknown. A timeout, skipped
phase, stale source, failed control or failed test cannot become PASS. Confirmed
resource cleanup can still release ownership after a verification failure.
Unproven cleanup remains HOLD with original handles retained.

The DLL is the historical frozen prebuilt52e7400f. This window does not build or
validate current native source. Thirty native debugger cases, performance, both
OHOS ABI builds, signed HAP and all installed-original checks remain separate.
No new examples may be added before installed originals pass.
