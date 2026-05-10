# Run every framework test (Lua unit suite + every smoke_*.ps1) and report a
# per-file pass/fail table plus a grand total and elapsed time.
#
# Each test script runs in its own pwsh process so an `exit 1` from a failing
# test does not abort the runner. Per-test PASS counts are extracted by
# counting `^PASS` lines in the captured output — both the smoke helpers
# (`PASS  <label>`) and the standalone Lua tests (`PASS <name>`) match.
#
# Requires:
#   - DCS running with the dcs-sms hook installed and the canonical test
#     mission loaded: framework/test/sms-framework-testing.miz (Syria, with
#     one ME-defined group and one circle zone — see _smoke.psm1 for the
#     fixture contract). Initialize-Smoke fails fast if any other map is
#     loaded.
#   - A Lua 5.1 interpreter on PATH (only for the Lua unit suite — the
#     smoke scripts run regardless).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $PSCommandPath

# Discovery order: Lua unit tests first (fast, no DCS bridge), then smoke.ps1
# (framework core), then smoke_*.ps1 alphabetically.
$scripts = @()
$lua = Join-Path $here 'run_distill_tests.ps1'
if (Test-Path $lua) {
    $scripts += [pscustomobject]@{ Name = 'run_distill_tests.ps1'; Path = $lua }
}
Get-ChildItem -Path $here -Filter 'smoke*.ps1' | Sort-Object Name | ForEach-Object {
    $scripts += [pscustomobject]@{ Name = $_.Name; Path = $_.FullName }
}

if ($scripts.Count -eq 0) {
    Write-Host "No test scripts found in $here" -ForegroundColor Yellow
    exit 1
}

$results = @()
$grandStart = Get-Date

foreach ($s in $scripts) {
    Write-Host ""
    Write-Host "=== $($s.Name) ===" -ForegroundColor Cyan
    $start = Get-Date
    $captured = & pwsh -NoProfile -File $s.Path 2>&1
    $exit = $LASTEXITCODE
    $elapsed = (Get-Date) - $start
    $captured | ForEach-Object { Write-Host $_ }
    # @(...) forces array semantics — Where-Object auto-unwraps a single
    # match into a scalar, which has no .Count.
    $passLines = @($captured | Where-Object { "$_" -match '^PASS\b' }).Count
    $results += [pscustomobject]@{
        Name    = $s.Name
        Tests   = $passLines
        Seconds = [math]::Round($elapsed.TotalSeconds, 1)
        Exit    = $exit
    }
}

$grandElapsed = (Get-Date) - $grandStart
$totalTests = ($results | Measure-Object Tests -Sum).Sum
if ($null -eq $totalTests) { $totalTests = 0 }
$failed = @($results | Where-Object { $_.Exit -ne 0 })

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $tag = if ($r.Exit -eq 0) { '[OK]  ' } else { '[FAIL]' }
    $color = if ($r.Exit -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("{0} {1,-25}  {2,4} tests  {3,6:N1}s" -f $tag, $r.Name, $r.Tests, $r.Seconds) -ForegroundColor $color
}
Write-Host "==========================================" -ForegroundColor Cyan
if ($failed.Count -eq 0) {
    Write-Host ("Ran {0} files, {1} tests in {2:N1}s — all green" -f $results.Count, $totalTests, $grandElapsed.TotalSeconds) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("Ran {0} files, {1} tests in {2:N1}s — {3} file(s) failed" -f $results.Count, $totalTests, $grandElapsed.TotalSeconds, $failed.Count) -ForegroundColor Red
    exit 1
}
