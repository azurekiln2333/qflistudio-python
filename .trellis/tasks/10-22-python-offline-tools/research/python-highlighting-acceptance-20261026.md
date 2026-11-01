# Python profile highlighting: consumer integration acceptance

Date: 2026-10-26. Task: `.trellis/tasks/10-22-python-offline-tools`.

Owned files for this item, source-author only:

- `test/python_highlighting_test.dart`
- `pubspec.yaml` (one `dev_dependencies` entry, described below)
- this note

Nothing was executed. No Flutter, Dart, analyzer, `pub get`, toolchain, native,
SDK, device or control command ran. The test is authored and unrun. No shared
core file, no other app test and no p6 edit was touched.

## The gap this covers

The shared engine already tokenizes Python: `qfli_studio_core` maps `.py` to
`langPython` and core's own test asserts a `keyword` scope for `return`. No test
in this app proved that the **python profile's real `.py` editor** turns that
tokenization into applied styling, or that the existing syntax-highlighting
setting reaches the editor. Core's tests call `Highlight` directly with a private
test renderer, so they never exercise the editor widget or the setting gate.

`test/python_highlighting_test.dart` closes that at the consumer boundary.

## What the test drives (real interfaces only)

- Theme: `HighlightThemes.themeFor(context, 'main.py', null, settings:)`, the
  same call `_EditorPageState._buildCodeView` makes with `settings:` and
  `ownerType:`. It returns the real `CodeHighlightTheme` for the python profile.
- Editor: the real `CodeEditor` with
  `CodeEditorStyle(codeTheme: theme)`, as `EditorPage` constructs it.
- Engine: the editor's own highlight path. `_CodeHighlighter` serialises the
  buffer into an isolate and runs re_highlight `Highlight` with the registered
  `langPython` mode.
- Observation: the public gutter seam. The test supplies
  `indicatorBuilder` returning `DefaultCodeLineNumber`, then reads
  `notifier.value!.paragraphs` (`List<CodeLineRenderParagraph>`). Each entry
  exposes `paragraph` (`IParagraph`), and
  `paragraph.getSpanForPosition(TextPosition(offset: n))` returns the leaf
  `TextSpan` that carries the applied color.

No fake renderer, no hardcoded span list, no golden image. Expected colors are
read from the returned theme itself (`theme.theme['keyword']!.color`), so the
assertions follow the real palette instead of a duplicated constant.

Fixture, fixed and narrow:

```
# note
def greet(name):
    text = "hello"
    return text
```

Probes are character offsets inside real tokens: `comment` (line 0), `def`
keyword (line 1), `string` at `"hello"` (line 2), `return` keyword (line 3).

## The three tests

1. Python profile produces real token styling. Waits for the isolate highlight
   to land the palette colors at all four probes, then asserts the applied
   color for `keyword`, `string` and `comment`, asserts the three differ, checks
   each line length against the source, and checks the leaf span text
   (`def`, `"hello"`).
2. The existing setting is respected. `await settings.setSyntaxHighlighting(false)`
   must make `themeFor` return null, and after a bounded settle no probe carries
   a token color and all probes share one color.
3. Re-open keeps behavior. After the tokens appear, the editor is unmounted,
   the controller disposed, and a fresh controller over the same source is
   opened again. The same four colors must come back.

## Observation strength and limits

Source review confirms that the setting and re-open tests observe the editor's
rendered spans, not only theme construction. In both cases `_indicator(tester)`
reads paragraphs produced by a really mounted `CodeEditor`, and
`paragraph.getSpanForPosition` returns the styled leaf. If the editor ignored the
setting or failed to restyle after re-open, the probe colors would not match and
the test would fail. It cannot pass on theme construction alone.

Limits recorded honestly:

- The setting is applied before the editor is mounted. The test proves the
  setting is honoured on the editor open/build path, which is the real
  `EditorPage` gate. It does not prove a live toggle on an already mounted
  editor. A live-toggle case would need a rebuild with a new theme instance.
- The re-open case compares the second editor's observed colors against the
  palette (`theme.theme[...]`), the same expectation the first open uses. It
  proves re-open reproduces the palette styling. It does not literally diff
  first-run observed values against second-run observed values.
- Only `TextStyle.color` is compared. Font weight, font style and decoration are
  not asserted, and leaf text is checked for two probes only.
- The disabled case asserts that no probe differs from one baseline taken from
  the keyword probe. It proves absence of per-token color differentiation, not a
  specific neutral color, because the test sets no `textColor`.
- The negative case is meaningful only together with the positive case on the
  same fixture. Read alone, "no token color" could pass vacuously. The file keeps
  both, so the pair is the evidence.
- Observation goes through the public gutter notifier, which publishes the same
  paragraphs the editor builds. The test does not intercept the paint call, so
  it observes that published paragraph rather than the painted canvas.
- `getSpanForPosition` returns null at or past `length - 1`, so every probe is an
  interior offset by construction.

## Manifest change: re_editor becomes a declared dev dependency

`pubspec.yaml` gained exactly one entry under `dev_dependencies`:

```yaml
  # test 需要 re_editor 的编辑器类型。
  # path override 仍指向 vendored 0.10.0，lock 不选网络版本。
  re_editor: ^0.10.0
```

The existing `dependency_overrides` block is unchanged and still points at
`../qfli_studio_core/vendor/re_editor`.

Why this is the right declaration, not a workaround:

- `flutter_lints` enables `depend_on_referenced_packages`. The quality spec
  states that direct package imports require direct pubspec dependencies, so the
  test import and the manifest entry now agree.
- The vendored package is genuinely `version: 0.10.0`, so `^0.10.0` matches what
  the override resolves to. The override still wins, so dependency selection
  stays on the local path and does not select a network version.
- `pubspec.lock` already records re_editor as `dependency: "direct overridden"`
  with `source: path` and `version: "0.10.0"`. That entry already carries both
  facts, so no lock edit is required or permitted here.
- No manual change was made to `pubspec.lock` or to `.dart_tool/package_config.json`.
  `pubspec.lock` still shows no modification.

Still pending, and explicitly not done: offline `pub get` resolution, `flutter
analyze`, and `flutter test`. All three need a fresh host grant. Nothing here
claims a resolved dependency graph or a passing analyzer.

## Source obstacle and its remaining limits

The import obstacle is resolved at the declaration level. Two limits stay
recorded for accuracy:

- This file suppresses no lint. It previously carried one
  `// ignore: depend_on_referenced_packages`. Root asked to remove it, and it is
  gone. Do not re-add it.
- Second limit, recorded for accuracy: `EditorPage` itself cannot be driven for
  span observation in a test, because its `indicatorBuilder` notifier is
  internal and highlight spans end up in a canvas `ui.Paragraph`, not a widget
  tree. The test therefore composes `CodeEditor` with the exact theme call
  `EditorPage` uses. Full-page coverage (file tree, tabs, minimap) is a separate
  acceptance item and stays open.
- Third detail: `themeFor` caches on settings identity, revision and brightness.
  Assigning `settings.syntaxHighlighting` directly would keep a stale cached
  theme. The test uses `setSyntaxHighlighting()`, which bumps the revision.

## Chinese prose lint method and its source-code limitation

The project linter `scripts/ste-lint-zh.py` treats every Dart `;` as a prose
semicolon. Run over the whole `.dart` file it reported 103 hard violations, all
of them Dart statement terminators, not Chinese joins. Those are false
positives. The language semicolons must not be deleted and the linter must not
be weakened.

The reliable method is to extract only the newly authored Chinese prose:

```powershell
$cn = Get-Content test\python_highlighting_test.dart |
  Select-String -Pattern "testWidgets\('([^']*[\u4e00-\u9fff][^']*)'" |
  ForEach-Object { $_.Matches[0].Groups[1].Value }
Set-Content build\python-highlighting-zh-prose.md -Value ($cn -join "`n") -Encoding UTF8
python scripts\ste-lint-zh.py build\python-highlighting-zh-prose.md
```

That extraction holds only the three test labels and reports 0 hard violations
at baseline 0. The build markdown is ignored by git, so it never ships.

Current Chinese surface is exactly three concise test labels:

- `python 配置的 .py 编辑器产出关键字、字符串与注释 token 样式`
- `关闭语法高亮后编辑器不再产出 token 样式`
- `重开 .py 编辑器后 token 样式保持不变`

All other comments and `reason:` strings are short English. This keeps the
Chinese prose surface small and lintable without touching language syntax.

## Facts the test relies on (read from source, not assumed)

- `HighlightThemes._extToLang` maps `.py` to `python`, and `_languages` binds
  `python` to `langPython`.
- `vsTheme` (used for light brightness, the default `highlightTheme` of
  `system`) defines `comment`, `keyword`, `string`. It does not define `number`,
  so this test does not assert a number color.
- `langPython` emits `className: 'comment'`, `'string'` and `'number'`, while
  keywords
  resolve to `keyword`, matching core's existing python assertion.
- `_HighlightLineRenderer.openNode` truncates a scope to its first dotted
  segment, so `keyword.control.python` becomes `keyword`.
- `InlineSpan.getSpanForPosition` walks children and returns the leaf span that
  contains the offset, which is the span carrying the token color.

## Current state

Authored, not run. No pass claim of any kind is made here. Offline `pub get`
resolution, `flutter analyze` and
`flutter test test/python_highlighting_test.dart` are later host-grant gates.
Nothing was executed for this note.

Scope of the claim: the test proves the python profile's `.py` theme path drives
the real editor's token spans and respects the existing highlighting setting.
It does not claim any app-level profile registration beyond that real `.py`
editor theme path. If a later run contradicts an assertion, the assertion is
what changes, not the product.

## Frozen inputs

Frozen now. Do not edit without root approval.

| File | Bytes | SHA256 |
| --- | --- | --- |
| `test/python_highlighting_test.dart` | 9680 | `bb094416539aecc3f9efe68ad0dc5a66ffbbda4ed3cc9384006dff7a2ba76d24` |
| `pubspec.yaml` | 1039 | `633852704d969d211ce942e64e2c59b7460c386e3dc1eb5460b0d4d5cab85879` |

Specs consulted before this change, per the before-dev checklist:
`.trellis/spec/frontend/index.md`, `directory-structure.md` (ownership map and
validation matrix) and `quality-guidelines.md` (direct imports need direct
dependencies, run `flutter analyze` and `flutter test`, `--no-pub` when already
resolved).

The Chinese comments in this change were checked with
`scripts/ste-lint-zh.py` on the extracted comment text and report 0 hard
violations. The pre-existing `path:` comment in `pubspec.yaml` is a p6 edit and
was left untouched.
