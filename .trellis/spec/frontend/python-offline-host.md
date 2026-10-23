# Standalone OHOS platform policy

## Scope and contract

The Python standalone host is offline at both the shared profile and native
MethodChannel boundaries. `EntryAbility.ets` declares `OFFLINE_ONLY = true`.
`qflistudio/platform` rejects `openAgreement` and `openUrl`, and
`qflistudio/huawei_account` rejects `login`, with error code `OFFLINE_ONLY`.
Refuse before argument access, router/browser navigation or account-provider
creation. All URL shapes, including loopback, file and custom schemes, are
refused: this Python edition has no browser-preview workflow.

Startup progress, local document selection and local text sharing retain their
existing handlers. Unknown methods still return notImplemented exactly once.
Keep this edition policy independent from startup progress and platform UI work.
The standalone module does not request `ohos.permission.INTERNET`.

## Verification

Run `node tool/test_python_offline_platform.cjs`. It transpiles and invokes the
actual EntryAbility handlers with local platform doubles. Its optional source
path argument permits executing the exact staged edition. Verify no remote
provider calls during registration or rejected requests, refusal before reading
arguments, one completion per request and preserved local handlers. A disabled
policy or historical unguarded source must fail the same regression.

This is behavioral host evidence. It does not establish ArkTS type checking,
packet-level behavior or installed-device acceptance. Inspect the final signed
HAP permission list independently. Bind its current source/FFI/library/asset
hashes, then verify the installed package: a previously signed HAP can remain
intact while no longer covering the current source tree.
