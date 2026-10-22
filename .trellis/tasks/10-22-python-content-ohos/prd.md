# Python all-example OHOS validation and expansion

## Goal and evidence

Satisfy parent R2/R3: every shipped Python learning program runs in this app's
OHOS interpreter, then expand with 180 new useful paired topics. Fresh parent
research finds 116/120 example passes with declared input, 115/120 tutorial
main-body passes without input, and ten compile failures among 186 exercise
answers. Direct CPython passes for four cases are not embedded acceptance.

## Requirements

- C1: Inventory all example, tutorial, exercise-answer and referenced project
  code, including setup/input/output fixtures and expected exits.
- C2: Repair every current embedded incompatibility, incomplete answer and lost
  fixture. Preserve existing IDs; do not hide failures behind CPython labels.
- C3: Verify the existing full inventory on installed OHOS before expansion.
- C4: Add at least 180 genuinely new, distinct practical topic pairs, resulting
  in at least 300 paired tutorials/examples with complete validated solutions.
- C5: Exercise real import-to-editor-to-run, not only verifier-injected source.
- C6: Preserve non-Python rows and all custom/edited persisted examples.

## Acceptance criteria

- [ ] Every runnable unit has executable setup, fixtures and expected behavior;
  no prose-only answer or undefined helper is miscounted as a passing program.
- [ ] All original units pass host VM and installed OHOS VM with zero omitted,
  unsupported, CPython-only or unexplained result rows before new authoring.
- [ ] Final 300+ pairs and all answer units pass the same exhaustive pipeline;
  titles/code/IDs are distinct and outputs deterministic.
- [ ] Imported input/project fixtures survive the actual common content import
  flow with correct overwrite/cancel behavior; current example008 is covered.
- [ ] Final asset/source consistency, pairing, preservation and rendering tests
  pass; reports identify revisions, unit hashes, fixture hashes and actual device.

## Boundaries and dependencies

Python authored content is under core's `tool/python_content/`; obtain narrow
exclusive file allocation before edits and serialize aggregate generation with
C/other language coordinators. C owns common fixture model/adapter/import fixes.
Module-dependent units wait for the module child. New content waits for the
original OHOS baseline. No detached host-CPython course or filler programs.
