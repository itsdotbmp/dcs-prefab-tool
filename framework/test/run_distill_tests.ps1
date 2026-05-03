# Locates a Lua 5.1 interpreter on PATH and runs all framework unit tests:
#   - test_utils_serialize.lua
#   - test_prefab_distill.lua
# Exits non-zero on any test failure or when no interpreter is available.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
Push-Location $here
try {
    $candidates = @('lua.exe', 'lua5.1.exe', 'lua51.exe')
    $lua = $null
    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $lua = $cmd.Source; break }
    }
    if (-not $lua) {
        Write-Host 'No Lua 5.1 interpreter found on PATH.' -ForegroundColor Yellow
        Write-Host 'Tried:' ($candidates -join ', ')
        Write-Host ''
        Write-Host 'Install Lua 5.1 (https://luabinaries.sourceforge.net/) and put it on PATH.'
        exit 2
    }
    Write-Host "Using Lua interpreter: $lua"
    $tests = @('test_utils_serialize.lua', 'test_prefab_distill.lua')
    $anyFailed = $false
    foreach ($t in $tests) {
        if (-not (Test-Path $t)) { continue }
        Write-Host ""
        Write-Host "=== $t ===" -ForegroundColor Cyan
        & $lua $t
        if ($LASTEXITCODE -ne 0) { $anyFailed = $true }
    }
    if ($anyFailed) { exit 1 } else { exit 0 }
} finally {
    Pop-Location
}
