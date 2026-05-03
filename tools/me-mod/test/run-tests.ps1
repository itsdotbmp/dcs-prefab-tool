# Locates a Lua 5.1 interpreter on PATH and runs test_serializer.lua.
# Exits non-zero on test failure or when no interpreter is available.

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
        Write-Host ''
        Write-Host 'Alternatively, run the test file directly inside DCS via:'
        Write-Host "  dcs-sms exec --file $(Join-Path $here 'test_serializer.lua')"
        exit 2
    }
    Write-Host "Using Lua interpreter: $lua"
    & $lua test_serializer.lua
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
