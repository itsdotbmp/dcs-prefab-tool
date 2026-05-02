# End-to-end smoke test for sms.timer v1.
# Drives the bridge with host-side sleeps to let sim time advance and
# verify timer callbacks fire as expected.
# Requires DCS running, mission loaded, and unpaused (sim must tick).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

Write-Host "==> hook status"
Invoke-Status

Write-Host "==> load framework files"
Invoke-Smoke -File 'sms.lua' | Out-Null
Invoke-Smoke -File 'log.lua' | Out-Null
Invoke-Smoke -File 'timer.lua' | Out-Null

Write-Host "==> bad-arg validation"
Expect-True -Label 'after: negative seconds returns nil' -Code 'return sms.timer.after(-1, function() end) == nil'
Expect-True -Label 'after: non-function fn returns nil' -Code 'return sms.timer.after(1, "not a function") == nil'
Expect-True -Label 'after: zero seconds is accepted (next-frame defer)' -Code 'return sms.timer.after(0, function() end) ~= nil'
Expect-True -Label 'every: zero seconds returns nil' -Code 'return sms.timer.every(0, function() end) == nil'
Expect-True -Label 'every: negative max returns nil' -Code 'return sms.timer.every(1, function() end, -3) == nil'

Write-Host "==> after fires once after delay"
Invoke-Smoke -Code @"
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.after(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)
"@ | Out-Null
Expect-True -Label 'after: handle is active immediately' -Code 'return _G._smoke.h:is_active()'
Start-Sleep -Seconds 2
Expect-Eq -Label 'after: fired count' -Code 'return _G._smoke.fired' -Expected 1
Expect-True -Label 'after: handle is no longer active' -Code 'return _G._smoke.h:is_active() == false'

Write-Host "==> every fires repeatedly until stopped"
Invoke-Smoke -Code @"
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)
"@ | Out-Null
Start-Sleep -Seconds 4
Expect-True -Label 'every: stop returns true when active' -Code 'return _G._smoke.h:stop()'
Expect-True -Label 'every: fired at least 3 times' -Code 'return _G._smoke.fired >= 3'
Expect-True -Label 'every: stop returns false on second call' -Code 'return _G._smoke.h:stop() == false'
Expect-True -Label 'every: handle is no longer active' -Code 'return _G._smoke.h:is_active() == false'

Write-Host "==> every with max stops after N fires"
Invoke-Smoke -Code @"
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end, 3)
"@ | Out-Null
Start-Sleep -Seconds 5
Expect-Eq -Label 'every with max: fired exactly 3 times' -Code 'return _G._smoke.fired' -Expected 3
Expect-True -Label 'every with max: handle is no longer active' -Code 'return _G._smoke.h:is_active() == false'

Write-Host "==> every self-cancels via fn returning false"
Invoke-Smoke -Code @"
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function()
    _G._smoke.fired = _G._smoke.fired + 1
    if _G._smoke.fired >= 2 then return false end
  end)
"@ | Out-Null
Start-Sleep -Seconds 3
Expect-Eq -Label 'every self-cancel: fired exactly 2 times' -Code 'return _G._smoke.fired' -Expected 2
Expect-True -Label 'every self-cancel: handle is no longer active' -Code 'return _G._smoke.h:is_active() == false'

Write-Host "==> get_remaining returns sensible values"
Invoke-Smoke -Code @"
  _G._smoke = {h = sms.timer.after(5, function() end)}
"@ | Out-Null
Expect-True -Label 'get_remaining initial (>4 and <=5)' -Code @"
  local r = _G._smoke.h:get_remaining()
  return type(r) == "number" and r > 4 and r <= 5.05
"@
Start-Sleep -Seconds 2
Expect-True -Label 'get_remaining after sleep (>2 and <4)' -Code @"
  local r = _G._smoke.h:get_remaining()
  return type(r) == "number" and r > 2 and r < 4
"@
Invoke-Smoke -Code '_G._smoke.h:stop()' | Out-Null

Write-Host "==> user errors in fn are caught"
Invoke-Smoke -Code @"
  _G._smoke = {h = sms.timer.every(1, function() error("boom from smoke test") end, 2)}
"@ | Out-Null
Start-Sleep -Seconds 3
Expect-True -Label 'errors caught: handle ran to max iterations' -Code 'return _G._smoke.h:is_active() == false'

Write-Host "==> verify [sms.timer] log lines for bad args and user errors"
Expect-LogContains -Label 'log: after seconds<0' -Pattern 'after: seconds must be a non-negative' -Grep '\[sms.timer\]'
Expect-LogContains -Label 'log: after fn non-fn' -Pattern 'after: fn must be a function'          -Grep '\[sms.timer\]'
Expect-LogContains -Label 'log: every seconds=0' -Pattern 'every: seconds must be a positive'     -Grep '\[sms.timer\]'
Expect-LogContains -Label 'log: every max<0'     -Pattern 'every: max must be a positive'         -Grep '\[sms.timer\]'
Expect-LogContains -Label 'log: user error'      -Pattern 'boom from smoke test'                  -Grep '\[sms.timer\]'

Write-Host ""
Write-Host "ALL smoke_timer checks passed."
