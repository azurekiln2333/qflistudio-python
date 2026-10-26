# Windows HDC file delivery

## 1. Scope and trigger

Use this contract when a serialized OHOS delivery grant permits file transfer.
A build grant does not itself grant target access. Preserve the existing HDC
server and use the exact assigned target and destination.

## 2. Signatures

```python
os.path.samefile(existing_server_executable, expected_hdc_executable)
run_owned(argv, timeout_seconds=work, cleanup_seconds=cleanup,
          cwd=repo, log_path=log, report_path=report)
```

```text
hdc list targets -v
hdc -t <exact-target> shell param get const.product.model
hdc -t <exact-target> file send <verified-local-hap> <assigned-destination>
hdc -t <exact-target> shell sha256sum <assigned-destination>
hdc -t <exact-target> shell stat -c %s <assigned-destination>
```

## 3. Contracts

Hash the local HAP immediately before transfer admission. Require its exact
expected size and SHA256. Confirm an existing server listener before invoking
HDC. Require an accessible server executable whose file identity matches the
pinned HDC executable. Windows may report its executable through an 8.3 path.
Textual path equality, even after case normalization, cannot establish identity.

Require the exact connected endpoint and expected model before owned ACK and
one send. Read only the assigned remote file for verification. A successful
send plus matching remote size and SHA256 establishes file delivery. It does
not establish installation, signing admission, launch or runtime acceptance.

## 4. Validation and error matrix

| Condition | Required result |
| --- | --- |
| Local size or hash drift | Stop before ACK/send |
| Missing listener or inaccessible/different executable | Stop before HDC client |
| Same executable through short and long paths | Accept file identity |
| Offline endpoint or unexpected model | Stop before ACK/send |
| Send nonzero or unavailable remote digest | Report failure or weaker evidence |
| Exact owned root not terminal or Job not empty | HOLD exact handles |
| Total deadline exceeded | Report budget failure separately from artifact result |

## 5. Good, base and bad cases

Good: short and long executable paths have the same file identity, the exact
endpoint/model match, and the remote hash and byte count match the signed HAP.
Base: every owned client terminates, its Job is empty and checked handles close.
Bad: a textual path mismatch becomes a claim that the HDC server is absent.

## 6. Required checks

Verify `samefile` against the actual reported short path and pinned long path
without executing HDC. Parse the transfer runner before admission. Retain each
original invocation, PID, creation FILETIME, Job, actual terminal, empty Job and
checked handle closure. Keep one original total deadline through final result
publisher terminal. Record later corroboration time separately. Never rebase.
No automatic retry follows a consumed grant.

## 7. Wrong and correct

Wrong: start another server after a textual short-path mismatch.
Correct: preserve the server, compare accessible file identities and request a
new transfer window after a consumed failed preflight.

Observed evidence: global998 failed before any HDC client because textual
comparison rejected the existing short path. Global1010 used the repaired
identity check and delivered the exact file with matching remote size/hash.
See [the delivery record](../../tasks/10-22-python-offline-tools/research/ohos-signed-build-20261026.md).
