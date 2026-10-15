# Writable root, content source, and provenance — targeted findings

Targeted lookups only (no full-repo scans). Confirms whether the Python content
can be delivered from `qfli_python` alone, and what provenance records carry.

## 1. Can `qfli_python` supply this content locally? — No, not without a core change

- The two pages are built **inside** `qfli_studio_core`:
  - `lib/pages/home_page.dart` (~L217/L226) constructs `LocalTutorialsTab` and
    `ExampleCodeTab` directly, passing only `language/store/auth/settings`
    (and `examples`), **not** a `repository`. So they default to
    `AssetContentRepository()`.
  - `lib/pages/local_content_pages.dart` (`LocalTutorialsTab`, `ExampleCodeTab`)
    accept an optional `repository`/`examples`, but nothing in `qfli_python`
    reaches that construction site.
- `StudioProfile` (`lib/services/studio_profile.dart`) exposes `id, appTitle,
  productKey, templates, runner, toolsPageBuilder, terminalCommandDelegate,
  documentToolBuilder, editorFileTools, entryFileNames, isOffline, showHomeTabs,
  runtimeKind, runtimeStatus, supportedFileExtensions` — **no** content
  repository / tutorial-page hook. `qfli_python/lib/main.dart` sets only these.
- `AssetContentRepository` (`lib/content/asset_content_repository.dart`) loads,
  in order: `packages/qfli_studio_core/assets/content/tutorials.json` then
  `assets/content/tutorials.json` (same for examples). The **package-prefixed
  key is tried first and exists**, so an app-declared
  `assets/content/tutorials.json` would not win.
- No language repo ships a local `assets/content/` (checked `qfli_java`,
  `qfli_dart`, `qfli_go`, `qfli_c`; none). `qfli_python/assets/` contains only
  `app_icon.png` and does not declare `assets/content/`.
- The legacy `assets/tutorials/python.json` is read by `TutorialService`, whose
  only callers are inside core/tests; the two visible pages use the aggregate
  catalog.
- On-device, the content is packaged into flutter_assets under
  `.../flutter_assets/packages/qfli_studio_core/assets/...`, i.e. it comes from
  the package, not the app.

**Conclusion**: there is no existing app-profile/asset-override route. Content
must be edited in `qfli_studio_core/assets/`, OR a new injection hook must be
added to core. Both are writes outside `qfli_python` and require approval.

## 2. Minimal external file scope (pending approval — nothing written)

If the team approves writing the shared package, the **minimum** set is:

| File | Why |
|---|---|
| `qfli_studio_core/assets/content/tutorials.json` | The 教程 tab's actual data source (Python entries only; other languages byte-preserved). |
| `qfli_studio_core/assets/content/examples.json` | The 示例代码 tab's actual data source (Python entries only). |
| `qfli_studio_core/assets/tutorials/python.json` | Legacy bundle loaded by `TutorialService`; currently short/stale runtime metadata. |
| `qfli_studio_core/tool/python_content/*` (new) + `tool/generate_python_content.dart` + `tool/verify_python_content.dart` (new) | Authored content + reproducible generation + real-runtime verification. |
| `qfli_studio_core/lib/services/example_code_store.dart` | Provenance-safe refresh of obsolete built-in records (see §3). |
| `qfli_studio_core/test/*` (focused) | Content integrity, migration/preservation, asset-loading, and render checks. |

Alternative with **zero** core content edits: add an optional content-repository
(or content-root) hook to `StudioProfile` and supply it from `qfli_python`.
That still requires editing `studio_profile.dart` + `home_page.dart` (smaller
content surface, but a wider API change). Enumerated for decision; not chosen
unless approved.

## 3. Provenance — the migration hazard is real

`ExampleCode` (in `lib/models/tutorial.dart`) carries only:
`id, type, title, summary, code, output, sourceLessonId`. There is **no**
`builtIn` flag and **no** per-record content version.

`ExampleCodeStore` (`lib/services/example_code_store.dart`):
- Tracks bundled defaults in `_defaults` (seeded via `seed(defaults)`) and user
  records in `_custom`. `items` overlays `_custom[id] ?? _defaults[id]`.
- Persists **only `_custom`** to `<app storage>/examples.json`, tagged with a
  single document-level `contentVersion`.
- Existing migration: when `storedVersion < contentVersion`, it removes every
  persisted record whose `type == 'java'`.

Implication: `type == 'python'` is **not** safe provenance — a user could have
saved/imported a Python example (type `python`) that would be wrongly deleted.
A Python purge keyed on `type` alone would destroy user data.

### Decision (final): refresh-only, preserve all user records

Because no reliable provenance exists, use a **refresh that never deletes any
record**:

1. Built-in defaults are always re-seeded from the new bundled catalog, so old
   built-in Python padding is **replaced in the UI** (a user who never edited a
   Python example sees only the new 120; obsolete built-in records simply no
   longer appear as defaults).
2. Persisted `_custom` records are **preserved wholesale** — never dropped by
   type, heuristic, or content comparison. No cleanup/removal flow is added. A
   user's saved override for a surviving built-in id still wins; a saved record
   for an obsolete built-in id becomes user-owned data and is kept.
3. No provenance marker and no obsolete-record purge are added.

No record is ever removed for any reason.

## 4. Decisions

- **D1 (blocking, still open)**: approve editing `qfli_studio_core/assets/*`
  (+ its generator/verifier/tests + the store refresh) as listed in §2, or
  instead approve a core API hook (`StudioProfile` content repository) supplied
  from `qfli_python`. Without one of these, the content cannot ship.
- **D2 — decided**: refresh-only, preserving all `_custom` user records; no
  cleanup/deletion path. Not a user choice.
