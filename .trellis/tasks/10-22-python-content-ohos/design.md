# Exhaustive content verification design

Build a single Python unit inventory from the actual shipped assets plus
authored source, preserving sourceLessonId and precise origin/field. Each unit
records code, setup, input/project files, expected stdout/stderr/exit and hashes.
Treat exercise answers as separate executable units in their declared context;
syntax success alone is insufficient. Compare aggregate/legacy/authored forms.

First repair original units, including the four CPython-only mains and malformed
or incomplete exercise solutions. Prefer supported equivalents with correct
teaching descriptions; preserve IDs and do not retain false compatibility labels.
Request C's common owner to preserve typed input/project fixtures through
ContentExampleEntry -> ExampleCode -> CodeImportService. Exercise008 must work
after ordinary UI import, not only a verifier's direct stdin injection.

Host verifier invokes the actual embedded DLL with a fresh isolated project per
unit. The app-owned OHOS audit harness loads the same inventory/materializes
fixtures and invokes PythonProgramRunner through the actual ArkTS/NAPI/VM.
Reports include every unit and finite timeout/failure states, actual runtime
version, HAP/SO/asset hashes and target identity. Do not run a parallel CPython
success path to satisfy embedded status. Separate channel doubles from runtime.

After original installed-OHOS acceptance, author 180 new practical topics across
data processing, algorithms, modules, packages, file formats, tests and supported
object-oriented patterns. Each adds a useful learning objective, deterministic
multi-line code, explained pitfalls and complete exercises. Reuse the authored
pipeline and stable ID allocation; content-only files have exclusive owners,
while aggregate JSON generation has one serialized writer per window.

Preserve every non-Python record and custom stored edit; failed generation or
audit keeps the previous content and reports the defect. Rollback content source
and generated owned Python segments together. No stale external report is
overwritten or used as current release evidence.
