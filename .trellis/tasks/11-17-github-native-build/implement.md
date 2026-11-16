# Execution plan

1. Record local disk and source status; confirm GitHub access.
2. Verify fixed toolchain acquisition and runner compatibility.
3. Implement hosted native workflows and concise artifact documentation.
   Current scope: remove Windows/Linux publication, retain Android/OHOS, add Apple.
4. Parse/lint workflow YAML and review commands against existing build targets.
5. Dispatch a Trellis check agent for the complete change.
6. Commit task-owned changes on a dedicated branch and push to the explicit GitHub URL.
7. Observe the resulting Actions run; inspect failures and fix/re-run as needed.
8. Download the small published artifacts, verify checksums and library formats.
9. Record actual results, update build guidance/specs, and finish the task.

## Verification

- actionlint for workflow syntax and expressions.
- Existing native debugger tests on the hosted Mac.
- OHOS check_so_deps.py and provenance tooling where applicable.
- Android llvm-readelf dependency/segment inspection.
- Apple lipo/otool/nm and XCFramework plist slice inspection.
- Artifact ZIP content and SHA256 inspection after download.
- git diff --check before committing.
- scripts/ste-lint-zh.py for any edited Chinese technical documentation.

No new full local SDK builds are needed for a workflow-only task. CI checks establish
native build/runtime results only for the targets actually executed.
