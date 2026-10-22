# Python offline breakpoint debugger

## Goal and evidence

Satisfy the feasible Python portion of parent R8 with real native breakpoint
pauses, step, continue and stop. Current upstream trace support is compiled off;
Stop and buffered logs are not a breakpoint debugger. Shared debugStream belongs
to web previews and is not a general Python debugger contract.

## Requirements

- D1: Use the real MicroPython trace machinery for project file/line breakpoints
  and line stepping; ordinary runs preserve behavior and cost when debug is off.
- D2: Expose actual paused location/stack and continue/step/stop controls through
  bounded session-owned events. Display variables only if genuinely available;
  absent frame-local support cannot be represented with fabricated values.
- D3: Pause control stays responsive on OHOS; session teardown, errors and stop
  release the VM/tokens and allow a successful subsequent normal run.
- D4: Consume C's common debugger/panel contract. Debug Console is useful for
  real debugger events; no remote debugging, network transport or fake Ports UI.

## Acceptance criteria

- [ ] An installed OHOS program pauses before the expected project source line,
  steps to the next executable line, continues to a second breakpoint and exits
  with the expected program result. A nondebug run matches prior behavior.
- [ ] Stop during pause and execution, disposal, runtime error and queued starts
  settle once, free native resources and recover on a new run.
- [ ] Imported project modules/Unicode paths and stale/removed breakpoint lines
  have defined tested behavior; system/bundled frames do not create false stops.
- [ ] Streamed events have actual session identity/order and bounded buffering;
  logs/stack capabilities are accurately labeled and no debugger result is faked.
- [ ] Real native tests, channel/FFI mapping tests, app suite, OHOS build/parity
  and installed-device debugger scenarios pass.

## Dependencies and exclusions

Wait for modules' native file batch before overlapping bridge/config/generator
edits. Wait for C's common debug API before shared-surface hookup. Own Python
native/FFI/platform adapters and app debugger integration only, not core UI.
No host debugger subprocess, arbitrary eval/watch claims or remote/port flows.
