param(
    [ValidateSet("release", "debug")]
    [string]$Configuration = "release"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root "core/Cargo.toml"

$cargoArgs = @("build", "--manifest-path", $manifest, "-p", "via-ffi")
if ($Configuration -eq "release") {
    $cargoArgs += "--release"
}

cargo @cargoArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$dll = Join-Path $root "core/target/$Configuration/via_core.dll"
$msvcDll = Join-Path $root "core/target/x86_64-pc-windows-msvc/$Configuration/via_core.dll"

if (Test-Path $dll) {
    Write-Host "Policy core: $dll"
} elseif (Test-Path $msvcDll) {
    Write-Host "Policy core: $msvcDll"
} else {
    Write-Error "via_core.dll was not produced"
    exit 1
}
