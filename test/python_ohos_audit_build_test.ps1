# Synthetic artifact/source-binding regressions. No Flutter, signing, native VM,
# HAP build or device process runs. Invoke the actual builder's function ASTs.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$builder = Join-Path $repo 'tool/build_python_ohos_audit.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($builder, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Builder PowerShell syntax is invalid.' }
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$temporary = Join-Path (Join-Path $repo 'build') ('audit-binding-test-' + [Guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $temporary 'product'
$coreRoot = Join-Path $temporary 'core'
$generatedDirectory = Join-Path $projectRoot 'build/python_content_audit'
$nativePath = Join-Path $projectRoot 'ohos/entry/libs/x86_64/libqfli_py.so'
$LlvmStrip = Join-Path $temporary 'no-strip-tool'
$checks = 0

function Write-Bytes([string]$Path, [byte[]]$Bytes) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllBytes($Path, $Bytes)
}
function Write-Text([string]$Path, [string]$Text) {
    Write-Bytes $Path ([Text.Encoding]::UTF8.GetBytes($Text))
}
function Expect-Rejected([scriptblock]$Action, [string]$Reason) {
    $seen = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Reason*") { throw "Wrong rejection: $($_.Exception.Message); expected $Reason" }
        $seen = $true
    }
    if (-not $seen) { throw "Expected rejection: $Reason" }
    $script:checks++
}
function Make-Hap([string]$Name, [hashtable]$Changes = @{}, [switch]$Internet, [switch]$DuplicateAsset, [string]$KernelText = '') {
    $path = Join-Path $temporary ($Name + '.hap')
    $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $permissions = @([ordered]@{ name = 'ohos.permission.READ_PASTEBOARD' })
        if ($Internet) { $permissions += [ordered]@{ name = 'ohos.permission.INTERNET' } }
        $module = [ordered]@{ module = @{ requestPermissions = $permissions } } | ConvertTo-Json -Depth 6 -Compress
        if ($KernelText -eq '') { $KernelText = 'synthetic-kernel:' + $inputs.buildMetadata.buildNonce + ':' + $inputs.suiteSha256 + ':' + $inputs.inventorySha256 }
        $kernel = [Text.Encoding]::UTF8.GetBytes($KernelText)
        Write-Bytes (Join-Path $projectRoot 'build/ohos/intermediates/flutter/defaultDebug/flutter_assets/kernel_blob.bin') $kernel
        $entries = @{
            'module.json' = [Text.Encoding]::UTF8.GetBytes($module)
            'libs/x86_64/libqfli_py.so' = $elf
            'libs/x86_64/libflutter.so' = $elf
            'resources/rawfile/flutter_assets/kernel_blob.bin' = $kernel
        }
        foreach ($asset in @(Get-AuditAssets $inputs)) {
            $entries['resources/rawfile/flutter_assets/' + $asset.AssetPath] = [IO.File]::ReadAllBytes($asset.SourcePath)
        }
        foreach ($key in $Changes.Keys) { $entries[$key] = $Changes[$key] }
        if ($DuplicateAsset) {
            $first = @(Get-AuditAssets $inputs)[0]
            $entries['duplicate/flutter_assets/' + $first.AssetPath] = [IO.File]::ReadAllBytes($first.SourcePath)
        }
        foreach ($name in $entries.Keys) {
            $entry = $zip.CreateEntry($name)
            $stream = $entry.Open()
            try { $stream.Write($entries[$name], 0, $entries[$name].Length) }
            finally { $stream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    return $path
}

try {
    [byte[]]$elf = New-Object byte[] 20
    $elf[0] = 127; $elf[1] = 69; $elf[2] = 76; $elf[3] = 70; $elf[4] = 2; $elf[5] = 1; $elf[18] = 62
    Write-Bytes $nativePath $elf
    Write-Text (Join-Path $projectRoot 'lib/runtime.dart') 'runtime-source'
    Write-Text (Join-Path $coreRoot 'lib/services/code_import_service.dart') 'core-import-source'
    Write-Text (Join-Path $coreRoot 'lib/services/debug_session.dart') 'core-debug-contract'
    Write-Text (Join-Path $projectRoot 'assets/python_stdlib/probe.py') 'print(42)'
    Write-Text (Join-Path $projectRoot 'native/tests/suite.py') 'assert 42 == 42'
    Write-Text (Join-Path $projectRoot 'build/inventory.json') '{"units":[]}'
    foreach ($name in @('assets/content/tutorials.json', 'assets/content/examples.json', 'assets/tutorials/python.json')) {
        Write-Text (Join-Path $coreRoot $name) '{}'
    }
    $bundleHash = Get-ByteHash ([IO.File]::ReadAllBytes((Join-Path $projectRoot 'assets/python_stdlib/probe.py')))
    $inputs = [pscustomobject]@{
        sourceDigests = [pscustomobject]@{ 'lib/runtime.dart' = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('runtime-source')) }
        coreSourceDigests = [pscustomobject]@{ 'lib/services/debug_session.dart' = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('core-debug-contract')) }
        assetDigests = [pscustomobject]@{ 'assets/python_stdlib/probe.py' = $bundleHash }
        suiteSource = 'native/tests/suite.py'
        suiteSha256 = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('assert 42 == 42'))
        nativeLibrary = [pscustomobject]@{ sha256 = Get-ByteHash $elf; bytes = $elf.Length }
        inventorySource = Join-Path $projectRoot 'build/inventory.json'
        inventorySha256 = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('{"units":[]}'))
        coreImportSourceSha256 = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('core-import-source'))
        unitCount = 1158
        bundledModuleAssetDigests = [pscustomobject]@{ 'assets/python_stdlib/probe.py' = $bundleHash }
        buildMetadata = [pscustomobject]@{ buildNonce = '0123456789abcdef0123456789abcdef'; auditKind = 'modules' }
    }
    $AuditKind = 'modules'
    $result = Inspect-Hap (Make-Hap 'modules-valid') $inputs
    if (-not $result.offlinePermissionCheck -or -not $result.pythonNativeBinding.verified -or $result.bundledAssets.Count -ne 1) { throw 'Valid module binding failed' }
    $checks++
    Expect-Rejected { Inspect-Hap (Make-Hap 'old-kernel' -KernelText 'previous-audit-kernel') $inputs } 'lacks this invocation/suite identity'
    Expect-Rejected { Inspect-Hap (Make-Hap 'kernel-substitution' @{ 'resources/rawfile/flutter_assets/kernel_blob.bin' = [byte[]]@(3, 4) }) $inputs } 'kernel differs from this build output'
    $inputs.buildMetadata.auditKind = 'debugger'
    Expect-Rejected { Inspect-Hap (Make-Hap 'wrong-audit-kind') $inputs } 'Missing current audit invocation identity'
    $inputs.buildMetadata.auditKind = 'modules'
    Expect-Rejected { Inspect-Hap (Make-Hap 'internet' -Internet) $inputs } 'must not request INTERNET'
    Expect-Rejected { Inspect-Hap (Make-Hap 'asset-drift' @{ 'resources/rawfile/flutter_assets/assets/python_stdlib/probe.py' = [byte[]]@(99) }) $inputs } 'Packaged asset/input mismatch'
    Expect-Rejected { Inspect-Hap (Make-Hap 'duplicate' -DuplicateAsset) $inputs } 'Expected exactly one packaged asset'
    Expect-Rejected { Inspect-Hap (Make-Hap 'foreign-abi' @{ 'libs/arm64-v8a/foreign.so' = $elf }) $inputs } 'only x86_64'
    Write-Text (Join-Path $projectRoot 'lib/runtime.dart') 'changed'
    Expect-Rejected { Assert-AuditSources $inputs } 'Audit/runtime source changed'
    Write-Text (Join-Path $projectRoot 'lib/runtime.dart') 'runtime-source'
    Write-Text (Join-Path $coreRoot 'lib/services/debug_session.dart') 'changed'
    Expect-Rejected { Assert-AuditSources $inputs } 'Shared audit/runtime source changed'
    Write-Text (Join-Path $coreRoot 'lib/services/debug_session.dart') 'core-debug-contract'

    $AuditKind = 'content'
    $inputs.buildMetadata.auditKind = 'content'
    $inputs.assetDigests = [pscustomobject]@{
        'assets/content/tutorials.json' = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('{}'))
        'assets/content/examples.json' = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('{}'))
        'assets/tutorials/python.json' = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes('{}'))
    }
    $result = Inspect-Hap (Make-Hap 'content-valid') $inputs
    if ($result.bundledAssets.Count -ne 4 -or $result.inventoryUnits -ne 1158) { throw 'Content prefix/module mapping failed' }
    $checks++
    Write-Text $inputs.inventorySource 'changed'
    Expect-Rejected { Assert-AuditSources $inputs } 'inventory changed'
    Write-Text $inputs.inventorySource '{"units":[]}'
    Write-Text (Join-Path $coreRoot 'lib/services/code_import_service.dart') 'changed'
    Expect-Rejected { Assert-AuditSources $inputs } 'import implementation changed'
    Write-Text (Join-Path $coreRoot 'lib/services/code_import_service.dart') 'core-import-source'
    $AuditKind = 'debugger'
    $inputs.buildMetadata.auditKind = 'debugger'
    $inputs.assetDigests = $inputs.bundledModuleAssetDigests
    $result = Inspect-Hap (Make-Hap 'debugger-valid') $inputs
    if ($result.bundledAssets.Count -ne 1) { throw 'Debugger product asset mapping failed' }
    $checks++
    $snapshot = Copy-HapSnapshot (Make-Hap 'snapshot-source')
    $snapshotHash = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash
    $snapshotGuard = [IO.File]::Open($snapshot, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Expect-Rejected { [IO.File]::WriteAllText($snapshot, 'replacement') } ''
        if ((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash -ne $snapshotHash) { throw 'Snapshot changed under verification lock' }
    }
    finally { $snapshotGuard.Dispose() }
    Write-Output "PASS $checks synthetic audit asset/source/permission regressions; no native/device/build execution."
}
finally {
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    $expectedParent = [IO.Path]::GetFullPath((Join-Path $repo 'build')) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTemporary.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside build/' }
    if (Test-Path -LiteralPath $resolvedTemporary) { Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force }
}
