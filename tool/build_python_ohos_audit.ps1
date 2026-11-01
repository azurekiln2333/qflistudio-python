[CmdletBinding()]
param(
    [ValidateSet('modules', 'content', 'debugger')]
    [string]$AuditKind = 'modules',
    [string]$InventoryPath = 'build/python-content-original-shipped.json',
    [string]$LogPath = 'build/python-ohos-audit-build.log',
    [string]$ReportPath = 'build/python-ohos-audit-build.json',
    [string]$HapSignTool = '',
    [string]$Java = '',
    [string]$LlvmStrip = '',
    [string]$NativeBuildEvidence = 'native/build/cmake-x86_64/native-build-evidence.json',
    [ValidateRange(1, 1800)][int]$BuildTimeoutSeconds = 240
)

# The coordinator runs this during an exclusive Python build window. This does
# not install, launch, stop, reset or otherwise operate any device/emulator.
# Only the existing entry ABI selection is temporarily changed. Root signing
# configuration is never written, copied or printed.
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profilePath = Join-Path $projectRoot 'ohos/entry/build-profile.json5'
$rootProfilePath = Join-Path $projectRoot 'ohos/build-profile.json5'
$buildDirectory = Join-Path $projectRoot 'build'
$auditDirectoryName = switch ($AuditKind) {
    'content' { 'python_content_audit' }
    'debugger' { 'python_debugger_audit' }
    default { 'python_module_audit' }
}
$generatedDirectory = Join-Path $buildDirectory $auditDirectoryName
$target = "build/$auditDirectoryName/main.dart"
$generatedPayload = $(if ($AuditKind -eq 'content') { 'inventory.g.dart' } else { 'suite.g.dart' })
$coreRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '../qfli_studio_core'))
$nativePath = Join-Path $projectRoot 'ohos/entry/libs/x86_64/libqfli_py.so'
[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null

function Resolve-ProjectPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $projectRoot $Path))
}

function Get-ByteHash([byte[]]$Bytes) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Get-EntryHash($Entry) {
    $stream = $Entry.Open()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Invoke-AuditTool([string]$Program, [string[]]$Arguments, [string]$Log, [int]$TimeoutSeconds = 30) {
    $stepPath = Join-Path $generatedDirectory ('process-' + [Guid]::NewGuid().ToString('N') + '.json')
    & $python (Join-Path $projectRoot 'tool/python_owned_process.py') --timeout-seconds $TimeoutSeconds --cleanup-seconds 10 `
        --cwd $projectRoot --log $Log --report $stepPath -- $Program @Arguments | Out-Null
    $wrapperExit = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $stepPath)) { throw 'Owned command did not produce process evidence.' }
    $step = Get-Content -LiteralPath $stepPath -Raw | ConvertFrom-Json
    $report.processes += $step
    if ($step.state -ne 'FINISHED' -or -not $step.cleanupConfirmed -or $step.release -ne 'RELEASE' -or
        ($null -ne $step.process -and (-not $step.process.terminal -or $step.process.jobActiveProcesses -ne 0 -or -not $step.process.handlesClosed))) {
        throw 'Owned command termination/cleanup was not confirmed.'
    }
    if ($wrapperExit -ne 0 -or $step.exitCode -ne 0) { throw "Audit command failed or timed out; process evidence: $stepPath" }
    return $step
}

function Assert-DartAuditPayload($Archive, $Inputs) {
    $entries = @($Archive.Entries | Where-Object { $_.FullName -match '/flutter_assets/kernel_blob\.bin$' })
    if ($entries.Count -ne 1) { throw 'The debug audit requires exactly one bound Dart kernel.' }
    $kernelPath = Join-Path $projectRoot 'build/ohos/intermediates/flutter/defaultDebug/flutter_assets/kernel_blob.bin'
    $bytes = [IO.File]::ReadAllBytes($kernelPath)
    $expectedHash = Get-ByteHash $bytes
    if ((Get-EntryHash $entries[0]) -ne $expectedHash) { throw 'Packaged Dart kernel differs from this build output.' }
    $nonce = [string]$Inputs.buildMetadata.buildNonce
    $kind = [string]$Inputs.buildMetadata.auditKind
    if ($nonce -notmatch '^[a-f0-9]{32}$' -or $kind -ne $AuditKind) { throw 'Missing current audit invocation identity.' }
    $decoded = [Text.Encoding]::UTF8.GetString($bytes)
    $suiteIdentity = $(if ($AuditKind -eq 'content') { $Inputs.inventorySha256 } else { $Inputs.suiteSha256 })
    if (-not $decoded.Contains($nonce) -or [string]::IsNullOrEmpty($suiteIdentity) -or -not $decoded.Contains($suiteIdentity)) {
        throw 'Compiled Dart kernel lacks this invocation/suite identity.'
    }
    return [ordered]@{ path = $entries[0].FullName; sha256 = $expectedHash; bytes = $entries[0].Length; buildNonce = $nonce; suiteIdentity = $suiteIdentity; verified = $true }
}

function Copy-HapSnapshot([string]$Source) {
    $destinationDirectory = Join-Path $projectRoot 'build/artifacts'
    [IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
    $destination = Join-Path $destinationDirectory ("python-$AuditKind-audit-" + [Guid]::NewGuid().ToString('N') + '.hap')
    $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $outputStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $inputStream.CopyTo($outputStream); $outputStream.Flush() }
        finally { $outputStream.Dispose() }
    }
    finally { $inputStream.Dispose() }
    return $destination
}

function Get-AuditAssets($Inputs) {
    foreach ($property in $Inputs.assetDigests.PSObject.Properties) {
        $fromCore = $AuditKind -eq 'content'
        [pscustomobject]@{
            AssetPath = $(if ($fromCore) { 'packages/qfli_studio_core/' + $property.Name } else { $property.Name })
            SourcePath = Join-Path $(if ($fromCore) { $coreRoot } else { $projectRoot }) $property.Name
            Sha256 = $property.Value
        }
    }
    if ($AuditKind -eq 'content') {
        foreach ($property in $Inputs.bundledModuleAssetDigests.PSObject.Properties) {
            [pscustomobject]@{
                AssetPath = $property.Name
                SourcePath = Join-Path $projectRoot $property.Name
                Sha256 = $property.Value
            }
        }
    }
}

function Assert-AuditSources($Inputs) {
    foreach ($property in $Inputs.sourceDigests.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $property.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $property.Value) {
            throw "Audit/runtime source changed during the build: $($property.Name)"
        }
    }
    foreach ($property in $Inputs.coreSourceDigests.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $coreRoot $property.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $property.Value) {
            throw "Shared audit/runtime source changed during the build: $($property.Name)"
        }
    }
    if ($AuditKind -eq 'content') {
        if ((Get-FileHash -LiteralPath $Inputs.inventorySource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Inputs.inventorySha256) {
            throw 'The original content inventory changed during the build.'
        }
        $importSource = Join-Path $coreRoot 'lib/services/code_import_service.dart'
        if ((Get-FileHash -LiteralPath $importSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Inputs.coreImportSourceSha256) {
            throw 'The shared content import implementation changed during the build.'
        }
    }
    else {
        $suitePath = Join-Path $projectRoot $Inputs.suiteSource
        if ((Get-FileHash -LiteralPath $suitePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Inputs.suiteSha256) {
            throw 'Portable module suite changed during the build.'
        }
    }
}

function Replace-One([string]$Text, [string]$Pattern, [string]$Replacement) {
    if ([regex]::Matches($Text, $Pattern).Count -ne 1) {
        throw 'The entry profile does not have exactly one expected ABI setting; no build was started.'
    }
    return [regex]::Replace($Text, $Pattern, $Replacement)
}

function Assert-X64Elf($Entry) {
    $stream = $Entry.Open()
    try {
        $header = New-Object byte[] 20
        $read = 0
        while ($read -lt $header.Length) {
            $count = $stream.Read($header, $read, $header.Length - $read)
            if ($count -eq 0) { break }
            $read += $count
        }
        if ($read -ne 20 -or $header[0] -ne 127 -or $header[1] -ne 69 -or
            $header[2] -ne 76 -or $header[3] -ne 70 -or $header[4] -ne 2 -or
            $header[5] -ne 1 -or [BitConverter]::ToUInt16($header, 18) -ne 62) {
            throw "Packaged native file is not ELF64 x86_64: $($Entry.FullName)"
        }
    }
    finally { $stream.Dispose() }
}

function Resolve-PythonNativeBinding($Packaged, $Inputs) {
    $currentNativeHash = (Get-FileHash -LiteralPath $nativePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $currentNativeBytes = (Get-Item -LiteralPath $nativePath).Length
    if ($currentNativeHash -ne $Inputs.nativeLibrary.sha256 -or $currentNativeBytes -ne $Inputs.nativeLibrary.bytes) {
        throw 'The staged Python SO changed after audit entry generation.'
    }
    $binding = [ordered]@{
        transform = 'identity'
        stagedPath = $nativePath
        stagedSha256 = $currentNativeHash
        stagedBytes = $currentNativeBytes
        packagedSha256 = $Packaged.sha256
        packagedBytes = $Packaged.bytes
        verified = $false
    }
    if ($Packaged.sha256 -eq $currentNativeHash -and $Packaged.bytes -eq $currentNativeBytes) {
        $binding.verified = $true
        return $binding
    }

    # Hvigor's worker/native-strip.js uses the SDK's default strip operation,
    # retaining .permission. Reproduce only that known transform on a separate
    # build copy; never strip/replace the staged input. A version string or
    # similarity check cannot substitute for an exact transformed-byte hash.
    if (-not (Test-Path -LiteralPath $LlvmStrip -PathType Leaf)) { throw 'SDK llvm-strip was not found.' }
    $transformedPath = Join-Path $generatedDirectory "native-binding-$PID.so"
    $stripLog = Join-Path $generatedDirectory 'native-binding-strip.log'
    $toolHash = (Get-FileHash -LiteralPath $LlvmStrip -Algorithm SHA256).Hash.ToLowerInvariant()
    $stripArguments = @('--keep-section=.permission', $nativePath, "-o$transformedPath")
    $stripStep = Invoke-AuditTool $LlvmStrip $stripArguments $stripLog
    $stripExit = $stripStep.exitCode
    if ($stripExit -ne 0 -or -not (Test-Path -LiteralPath $transformedPath -PathType Leaf)) {
        throw 'The exact SDK strip transform did not complete.'
    }
    $transformedHash = (Get-FileHash -LiteralPath $transformedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $transformedBytes = (Get-Item -LiteralPath $transformedPath).Length
    if ($transformedHash -ne $Packaged.sha256 -or $transformedBytes -ne $Packaged.bytes) {
        throw 'Packaged Python SO matches neither the staged input nor the exact SDK strip transform.'
    }
    if ((Get-FileHash -LiteralPath $nativePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $currentNativeHash -or
        (Get-FileHash -LiteralPath $LlvmStrip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $toolHash) {
        throw 'The staged SO or strip tool changed during native binding verification.'
    }
    $binding.transform = 'sdk-llvm-strip-default-keep-permission'
    $binding.transformArguments = $stripArguments
    $binding.transformContract = 'Hvigor tasks/worker/native-strip.js: LlvmCommandBuild.addKeepSection(.permission)'
    $binding.transformedPath = $transformedPath
    $binding.transformedSha256 = $transformedHash
    $binding.transformedBytes = $transformedBytes
    $binding.toolPath = $LlvmStrip
    $binding.toolSha256 = $toolHash
    $versionLog = Join-Path $generatedDirectory 'native-binding-strip-version.log'
    Invoke-AuditTool $LlvmStrip @('--version') $versionLog | Out-Null
    $binding.toolVersion = (Get-Content -LiteralPath $versionLog -Raw).Trim()
    $binding.transformExitCode = $stripExit
    $binding.verified = $true
    return $binding
}

function Inspect-Hap([string]$Path, $Inputs) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $moduleEntries = @($archive.Entries | Where-Object { $_.FullName -eq 'module.json' })
        if ($moduleEntries.Count -ne 1) { throw 'Expected one packaged module manifest.' }
        $reader = [IO.StreamReader]::new($moduleEntries[0].Open())
        try { $module = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        $permissions = @($module.module.requestPermissions | ForEach-Object { $_.name })
        if ($permissions -contains 'ohos.permission.INTERNET') {
            throw 'The offline Python package must not request INTERNET permission.'
        }
        $nativeEntries = @($archive.Entries | Where-Object { $_.FullName -match '^libs/[^/]+/[^/]+\.so$' })
        if ($nativeEntries.Count -eq 0 -or @($nativeEntries | Where-Object { $_.FullName -notmatch '^libs/x86_64/' }).Count -ne 0) {
            throw 'The emulator HAP must contain only x86_64 native libraries.'
        }
        foreach ($required in @('libqfli_py.so', 'libflutter.so')) {
            if (@($nativeEntries | Where-Object { $_.FullName -eq "libs/x86_64/$required" }).Count -ne 1) {
                throw "Required matching native runtime is missing: $required"
            }
        }
        $dartBinding = Assert-DartAuditPayload $archive $Inputs
        $libraries = @()
        foreach ($entry in $nativeEntries) {
            Assert-X64Elf $entry
            $libraries += [ordered]@{ path = $entry.FullName; bytes = $entry.Length; sha256 = Get-EntryHash $entry }
        }
        $native = @($libraries | Where-Object { $_.path -eq 'libs/x86_64/libqfli_py.so' })[0]
        $nativeBinding = Resolve-PythonNativeBinding $native $Inputs
        $assets = @()
        foreach ($asset in @(Get-AuditAssets $Inputs)) {
            $suffix = '/flutter_assets/' + $asset.AssetPath
            $entries = @($archive.Entries | Where-Object { $_.FullName.EndsWith($suffix, [StringComparison]::Ordinal) })
            if ($entries.Count -ne 1) { throw "Expected exactly one packaged asset: $($asset.AssetPath)" }
            $hash = Get-EntryHash $entries[0]
            $sourceHash = (Get-FileHash -LiteralPath $asset.SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $asset.Sha256 -or $hash -ne $sourceHash) { throw "Packaged asset/input mismatch: $($asset.AssetPath)" }
            $assets += [ordered]@{ path = $entries[0].FullName; bytes = $entries[0].Length; sha256 = $hash }
        }
        Assert-AuditSources $Inputs
        return [ordered]@{
            path = $Path
            bytes = (Get-Item -LiteralPath $Path).Length
            sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
            abi = 'x86_64'
            permissions = $permissions
            offlinePermissionCheck = $true
            nativeLibraries = $libraries
            pythonNativeBinding = $nativeBinding
            dartPayload = 'kernel_blob.bin'
            dartPayloadBinding = $dartBinding
            suiteSha256 = $Inputs.suiteSha256
            inventorySha256 = $Inputs.inventorySha256
            inventoryUnits = $Inputs.unitCount
            bundledAssets = $assets
        }
    }
    finally { $archive.Dispose() }
}

# The signing tool only verifies an already-signed HAP. It needs no credentials.
# Its output and extracted public signing data are never printed.
function Verify-HapSignature([string]$Path) {
    $certificatePath = Join-Path $generatedDirectory "verification-$PID.cer"
    $provisionPath = Join-Path $generatedDirectory "verification-$PID.p7b"
    $verifyLog = Join-Path $generatedDirectory 'signature-verification.log'
    try {
        $signatureStep = Invoke-AuditTool $Java @('-jar', $HapSignTool, 'verify-app', '-inFile', $Path, '-outCertChain', $certificatePath, '-outProfile', $provisionPath) $verifyLog
        $verifyExit = $signatureStep.exitCode
        if ($verifyExit -ne 0 -or -not (Test-Path -LiteralPath $certificatePath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $provisionPath -PathType Leaf)) {
            throw 'The SDK signing tool did not verify the fresh HAP signature.'
        }
        return [ordered]@{ verified = $true; exitCode = $verifyExit; toolSha256 = (Get-FileHash -LiteralPath $HapSignTool -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    finally {
        # These exact two generated files are within build/; no recursive or
        # computed cross-shell deletion is used.
        foreach ($path in @($certificatePath, $provisionPath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
}

$logFullPath = Resolve-ProjectPath $LogPath
$reportFullPath = Resolve-ProjectPath $ReportPath
foreach ($path in @($logFullPath, $reportFullPath)) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
}
if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) { throw 'Build/stage the reviewed x86_64 Python SO before this audit build.' }
$flutter = (Get-Command flutter -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$python = (Get-Command python.exe -CommandType Application -ErrorAction Stop | Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1).Source
if ([string]::IsNullOrEmpty($python)) { throw 'A real local Python executable is required.' }
$nativeManifestPath = Resolve-ProjectPath $NativeBuildEvidence
if (-not (Test-Path -LiteralPath $nativeManifestPath -PathType Leaf)) { throw 'Build a current SO with completed native-build-evidence.json before packaging.' }
if ([string]::IsNullOrEmpty($HapSignTool) -or [string]::IsNullOrEmpty($Java) -or [string]::IsNullOrEmpty($LlvmStrip)) {
    $sdkLine = @(Get-Content -LiteralPath (Join-Path $projectRoot 'ohos/local.properties') | Where-Object { $_ -match '^hwsdk\.dir=' })
    if ($sdkLine.Count -ne 1) { throw 'Pass -HapSignTool, -Java and -LlvmStrip, or configure the existing local hwsdk.dir.' }
    $sdkRoot = $sdkLine[0].Substring('hwsdk.dir='.Length).Replace('\\', '\').Replace('\:', ':')
    if ([string]::IsNullOrEmpty($HapSignTool)) { $HapSignTool = Join-Path $sdkRoot 'default/openharmony/toolchains/lib/hap-sign-tool.jar' }
    if ([string]::IsNullOrEmpty($Java)) { $Java = Join-Path (Split-Path -Parent $sdkRoot) 'jbr/bin/java.exe' }
    if ([string]::IsNullOrEmpty($LlvmStrip)) { $LlvmStrip = Join-Path $sdkRoot 'default/openharmony/native/llvm/bin/llvm-strip.exe' }
}
if (-not (Test-Path -LiteralPath $HapSignTool -PathType Leaf) -or -not (Test-Path -LiteralPath $Java -PathType Leaf) -or
    -not (Test-Path -LiteralPath $LlvmStrip -PathType Leaf)) {
    throw 'The local SDK signature verifier/Java/llvm-strip was not found; pass explicit paths.'
}
$lockPath = Join-Path $buildDirectory '.ohos-audit-build.lock'
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$originalBytes = $null
$hadJavaOptions = Test-Path Env:JAVA_TOOL_OPTIONS
$oldJavaOptions = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'Process')
$previousLocation = Get-Location
$started = [DateTime]::UtcNow
$report = [ordered]@{
    startedUtc = $started.ToString('o')
    target = $target
    auditKind = $AuditKind
    platform = 'ohos-x64'
    javaToolOptions = '-Xms16m -Xmx256m -XX:+UseSerialGC'
    buildExitCode = $null
    profileRestored = $false
    rootProfileUnchanged = $false
    environmentRestored = $false
    logPath = $logFullPath
    hap = $null
    processes = @()
    error = $null
}
try {
    $originalBytes = [IO.File]::ReadAllBytes($profilePath)
    $report.originalProfileSha256 = Get-ByteHash $originalBytes
    $report.originalRootProfileSha256 = (Get-FileHash -LiteralPath $rootProfilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $backupPath = Join-Path $buildDirectory "python-ohos-audit-profile-$($started.ToString('yyyyMMddTHHmmssfff'))-$PID.original"
    [IO.File]::WriteAllBytes($backupPath, $originalBytes)
    $report.recoveryProfilePath = $backupPath
    Set-Location -LiteralPath $projectRoot
    [IO.Directory]::CreateDirectory($generatedDirectory) | Out-Null
    $nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw | ConvertFrom-Json
    if ($nativeManifest.abi -ne 'x86_64') { throw 'The audit needs completed x86_64 native build provenance.' }
    Invoke-AuditTool $python @((Join-Path $projectRoot 'tool/python_native_provenance.py'), 'verify', '--manifest', $nativeManifestPath, '--library', $nativePath) (Join-Path $generatedDirectory 'native-provenance-before.log') | Out-Null
    $report.nativeBuildEvidencePath = $nativeManifestPath
    $report.nativeBuildEvidenceSha256 = (Get-FileHash -LiteralPath $nativeManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $report.buildNonce = [Guid]::NewGuid().ToString('N')
    $metadataPath = Join-Path $generatedDirectory 'build-metadata.json'
    [ordered]@{ buildNonce = $report.buildNonce; auditKind = $AuditKind; nativeBuildEvidenceSha256 = $report.nativeBuildEvidenceSha256 } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    if ($AuditKind -eq 'content') {
        $prepareArguments = @((Join-Path $PSScriptRoot 'prepare_python_content_audit.py'), '--inventory', (Resolve-ProjectPath $InventoryPath), '--native-library', $nativePath, '--build-metadata', $metadataPath)
    }
    elseif ($AuditKind -eq 'debugger') {
        $prepareArguments = @((Join-Path $PSScriptRoot 'prepare_python_debugger_audit.py'), '--native-library', $nativePath, '--build-metadata', $metadataPath)
    }
    else {
        $prepareArguments = @((Join-Path $PSScriptRoot 'prepare_python_module_audit.py'), '--native-library', $nativePath, '--build-metadata', $metadataPath)
    }
    Invoke-AuditTool $python $prepareArguments (Join-Path $generatedDirectory 'prepare.log') | Out-Null
    $inputsPath = Join-Path $generatedDirectory 'inputs.json'
    $inputs = Get-Content -LiteralPath $inputsPath -Raw | ConvertFrom-Json
    $report.inputs = $inputs
    $report.targetSha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot $target) -Algorithm SHA256).Hash.ToLowerInvariant()
    $report.generatedPayload = $generatedPayload
    $report.generatedPayloadSha256 = (Get-FileHash -LiteralPath (Join-Path $generatedDirectory $generatedPayload) -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-AuditSources $inputs
    Invoke-AuditTool $python @((Join-Path $projectRoot 'tool/python_audit_inputs.py'), '--inputs', $inputsPath) (Join-Path $generatedDirectory 'inputs-before.log') | Out-Null
    $text = [Text.Encoding]::UTF8.GetString($originalBytes)
    $text = Replace-One $text '("abiFilters"\s*:\s*)\["arm64-v8a"\]' '${1}["x86_64"]'
    $text = Replace-One $text '("excludes"\s*:\s*\[)\s*"\*\*/x86_64/\*\*"(\s*,\s*"\*\*/armeabi-v7a/\*\*")?(\s*\])' '${1}"**/arm64-v8a/**"${2}${3}'
    [IO.File]::WriteAllText($profilePath, $text, (New-Object Text.UTF8Encoding($false)))
    $report.temporaryProfileSha256 = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $report.javaToolOptions, 'Process')
    Write-Output "Building the Python $AuditKind audit for x86_64; log: $logFullPath"
    $buildStep = Invoke-AuditTool $flutter @('build', 'hap', '--debug', '--no-pub', '--target-platform', 'ohos-x64', '-t', $target) $logFullPath $BuildTimeoutSeconds
    $report.buildExitCode = $buildStep.exitCode
    if ($report.buildExitCode -ne 0) { throw "Flutter HAP build failed with exit code $($report.buildExitCode)." }
    $outputs = Join-Path $projectRoot 'ohos/entry/build/default/outputs/default'
    $candidates = @(Get-ChildItem -LiteralPath $outputs -Filter 'entry-default-signed.hap')
    if ($candidates.Count -ne 1) { throw 'Expected exactly one signed entry HAP; the embedded nonce must prove this invocation.' }
    if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $target) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.targetSha256 -or
        (Get-FileHash -LiteralPath (Join-Path $generatedDirectory $generatedPayload) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.generatedPayloadSha256) {
        throw 'Generated Dart build inputs changed during the build.'
    }
    Assert-AuditSources $inputs
    Invoke-AuditTool $python @((Join-Path $projectRoot 'tool/python_audit_inputs.py'), '--inputs', $inputsPath) (Join-Path $generatedDirectory 'inputs-after.log') | Out-Null
    Invoke-AuditTool $python @((Join-Path $projectRoot 'tool/python_native_provenance.py'), 'verify', '--manifest', $nativeManifestPath, '--library', $nativePath) (Join-Path $generatedDirectory 'native-provenance-after.log') | Out-Null
    if ((Get-FileHash -LiteralPath $nativeManifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.nativeBuildEvidenceSha256) { throw 'Native provenance changed during packaging.' }
    $snapshot = Copy-HapSnapshot $candidates[0].FullName
    $snapshotLock = [IO.File]::Open($snapshot, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $report.hap = Inspect-Hap $snapshot $inputs
        $report.hap.signature = Verify-HapSignature $snapshot
        if ((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.hap.sha256) { throw 'HAP snapshot changed during verification.' }
        $report.hap.snapshotLockedDuringVerification = $true
        Assert-AuditSources $inputs
    }
    finally { $snapshotLock.Dispose() }
}
catch { $report.error = $_.Exception.Message }
finally {
    $ErrorActionPreference = 'Stop'
    try {
        if ($null -ne $originalBytes) {
            [IO.File]::WriteAllBytes($profilePath, $originalBytes)
            $report.restoredProfileSha256 = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $report.profileRestored = $report.restoredProfileSha256 -eq $report.originalProfileSha256
        }
        $report.finalRootProfileSha256 = (Get-FileHash -LiteralPath $rootProfilePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $report.rootProfileUnchanged = $report.finalRootProfileSha256 -eq $report.originalRootProfileSha256
    }
    finally {
        if ($hadJavaOptions) { [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $oldJavaOptions, 'Process') }
        else { Remove-Item Env:JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue }
        $report.environmentRestored = ((Test-Path Env:JAVA_TOOL_OPTIONS) -eq $hadJavaOptions) -and
            ([Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'Process') -eq $oldJavaOptions)
        Set-Location -LiteralPath $previousLocation.Path
        $lock.Dispose()
        $report.finishedUtc = [DateTime]::UtcNow.ToString('o')
        $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    }
}
if (-not $report.profileRestored -or -not $report.rootProfileUnchanged -or -not $report.environmentRestored) {
    throw "Build state restoration check failed; see $reportFullPath"
}
if ($null -ne $report.error) { throw "$($report.error) Report: $reportFullPath" }
Write-Output "Verified signed x86_64 Python audit HAP: $($report.hap.path)"
Write-Output "Entry profile/environment restored and root profile unchanged; report: $reportFullPath"
