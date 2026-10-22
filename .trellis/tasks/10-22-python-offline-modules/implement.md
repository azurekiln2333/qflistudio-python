# Module execution plan

1. After parent plan review, start this child and read runtime/FFI/quality specs.
2. Reconfirm current module probe and create a tested API/provenance inventory.
3. Add substantive compatible bundled modules with behavioral tests; register
   assets and implement project bundle preparation plus native import paths.
4. Implement local install/list/show/check/remove transactions and manifests;
   cover failure/cancel/conflict/project boundaries with real temporary files.
5. Expose the typed service to the tools child; coordinate any terminal command
   through this service rather than a second package installer.
6. Run focused Dart/native tests, full app analyzer/tests, FFI smoke, native host
   import/resource suite, OHOS native/dependency checks and installed module
   scenarios. Keep host/build/device gates separate while hdc is empty.
7. Review generated files and licenses, update runtime/module specs, commit only
   this child's owned files, then release native files to debugger work.

Validation: parent command matrix plus new module/package regressions. Do not
mirror implementation with import-only tests: exercise concrete module API
results and failed package transactions. Rollback only the transaction or owned
commit; preserve user files and preexisting WIP.
