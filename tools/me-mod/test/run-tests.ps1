# Locates a Lua 5.1 interpreter on PATH and runs all me-mod unit tests:
#   - test_serializer.lua
#   - test_serializer_parity.lua
#   - test_distill_parity.lua
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
        Write-Host 'To run these tests, install a Lua 5.1 interpreter and put it on PATH.'
        Write-Host 'Recommended for Windows: https://luabinaries.sourceforge.net/'
        exit 2
    }
    Write-Host "Using Lua interpreter: $lua"
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua')
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
