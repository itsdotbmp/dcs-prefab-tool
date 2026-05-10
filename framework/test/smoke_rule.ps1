# End-to-end smoke test for sms.rule v1.
# Drives the bridge with host-side sleeps to let sim time advance and verify
# the rule state machine. Requires DCS running, mission loaded, unpaused.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

Write-Host "==> hook status"
Invoke-Status

Write-Host "==> load framework files"
Invoke-Smoke -File 'sms.lua'   | Out-Null
Invoke-Smoke -File 'log.lua'   | Out-Null
Invoke-Smoke -File 'timer.lua' | Out-Null
Invoke-Smoke -File 'rule.lua'  | Out-Null

Write-Host "==> bad-arg validation"
Expect-True -Label "rule: empty name returns nil" `
  -Code 'return sms.rule("", {type=sms.rule.TYPE.ONCE, condition=function()end, action=function()end}) == nil'
Expect-True -Label "rule: non-table opts returns nil" `
  -Code 'return sms.rule("x", "not a table") == nil'
Expect-True -Label "rule: unknown type returns nil" `
  -Code 'return sms.rule("x", {type="banana", condition=function()end, action=function()end}) == nil'
Expect-True -Label "rule: missing condition returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.ONCE, action=function()end}) == nil'
Expect-True -Label "rule: missing action returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.ONCE, condition=function()end}) == nil'
Expect-True -Label "rule: zero interval returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.ONCE, interval=0, condition=function()end, action=function()end}) == nil'
Expect-True -Label "rule: negative cooldown returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.CONTINUOUS, cooldown=-1, condition=function()end, action=function()end}) == nil'
Expect-True -Label "rule: cooldown on ONCE returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.ONCE, cooldown=5, condition=function()end, action=function()end}) == nil'
Expect-True -Label "rule: negative sustain returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.ONCE, sustain=-1, condition=function()end, action=function()end}) == nil'
Expect-True -Label "rule: non-function dev_condition returns nil" `
  -Code 'return sms.rule("x", {type=sms.rule.TYPE.ONCE, dev_condition=42, condition=function()end, action=function()end}) == nil'

Write-Host "==> ONCE: fires once and unregisters"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0, allow = false}
  _G._smoke.h = sms.rule("smoke_once", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    condition = function() return _G._smoke.allow end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Expect-True -Label "ONCE: registered immediately" -Code 'return sms.rule.get("smoke_once") ~= nil'
Start-Sleep -Seconds 2
Expect-Eq -Label "ONCE: did not fire while condition false" -Code 'return _G._smoke.fires' -Expected 0
Invoke-Smoke -Code '_G._smoke.allow = true' | Out-Null
Start-Sleep -Seconds 3
Expect-Eq -Label "ONCE: fired exactly once" -Code 'return _G._smoke.fires' -Expected 1
Expect-True -Label "ONCE: unregistered after fire" -Code 'return sms.rule._rules["smoke_once"] == nil'

Write-Host "==> CONTINUOUS: fires every tick condition is true"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_continuous", {
    type      = sms.rule.TYPE.CONTINUOUS,
    interval  = 1,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Start-Sleep -Seconds 4
Invoke-Smoke -Code 'sms.rule.remove("smoke_continuous")' | Out-Null
Expect-True -Label "CONTINUOUS: fired at least 3 times" -Code 'return _G._smoke.fires >= 3'

Write-Host "==> TOGGLE: edge-triggered, refires after reset"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0, on = false}
  _G._smoke.h = sms.rule("smoke_toggle", {
    type      = sms.rule.TYPE.TOGGLE,
    interval  = 1,
    condition = function() return _G._smoke.on end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Invoke-Smoke -Code '_G._smoke.on = true' | Out-Null
Start-Sleep -Seconds 3
Expect-Eq -Label "TOGGLE: fired exactly once on rising edge" -Code 'return _G._smoke.fires' -Expected 1
Expect-True -Label "TOGGLE: handle reports active" -Code 'return _G._smoke.h:is_active()'
Invoke-Smoke -Code '_G._smoke.on = false' | Out-Null
Start-Sleep -Seconds 2
Expect-True -Label "TOGGLE: handle no longer active after falling edge" -Code 'return _G._smoke.h:is_active() == false'
Invoke-Smoke -Code '_G._smoke.on = true' | Out-Null
Start-Sleep -Seconds 2
Expect-Eq -Label "TOGGLE: refired on second rising edge" -Code 'return _G._smoke.fires' -Expected 2
Invoke-Smoke -Code 'sms.rule.remove("smoke_toggle")' | Out-Null
Expect-True -Label "TOGGLE: is_active() returns false after :stop() on an active TOGGLE" `
  -Code 'return _G._smoke.h:is_active() == false'

Write-Host "==> COOLDOWN gates fires"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_cooldown", {
    type      = sms.rule.TYPE.CONTINUOUS,
    interval  = 1,
    cooldown  = 3,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Start-Sleep -Seconds 4
Invoke-Smoke -Code 'sms.rule.remove("smoke_cooldown")' | Out-Null
Expect-True -Label "COOLDOWN: fired between 1 and 2 times in 4s with cooldown=3" `
  -Code 'return _G._smoke.fires >= 1 and _G._smoke.fires <= 2'

Write-Host "==> SUSTAIN delays first fire"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_sustain", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    sustain   = 3,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Start-Sleep -Seconds 2
Expect-Eq -Label "SUSTAIN: did not fire before sustain elapsed" -Code 'return _G._smoke.fires' -Expected 0
Start-Sleep -Seconds 3
Expect-Eq -Label "SUSTAIN: fired after sustain elapsed" -Code 'return _G._smoke.fires' -Expected 1

Write-Host "==> SUSTAIN resets when condition flickers false"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0, allow = true}
  _G._smoke.h = sms.rule("smoke_sustain_flicker", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    sustain   = 3,
    condition = function() return _G._smoke.allow end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Start-Sleep -Seconds 2
Invoke-Smoke -Code '_G._smoke.allow = false' | Out-Null
Start-Sleep -Seconds 1
Invoke-Smoke -Code '_G._smoke.allow = true' | Out-Null
Start-Sleep -Seconds 2
Expect-Eq -Label "SUSTAIN flicker: did not fire (sustain restarted)" -Code 'return _G._smoke.fires' -Expected 0
Start-Sleep -Seconds 2
Expect-Eq -Label "SUSTAIN flicker: fired after the sustained window" -Code 'return _G._smoke.fires' -Expected 1

Write-Host "==> dev_condition bypasses sustain and cooldown"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0, dev = false}
  _G._smoke.h = sms.rule("smoke_dev", {
    type          = sms.rule.TYPE.CONTINUOUS,
    interval      = 1,
    cooldown      = 999,
    sustain       = 999,
    condition     = function() return false end,
    dev_condition = function() return _G._smoke.dev end,
    action        = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Start-Sleep -Seconds 2
Expect-Eq -Label "dev_condition off: no fires" -Code 'return _G._smoke.fires' -Expected 0
Invoke-Smoke -Code '_G._smoke.dev = true' | Out-Null
Start-Sleep -Seconds 3
Invoke-Smoke -Code '_G._smoke.dev = false' | Out-Null
Invoke-Smoke -Code 'sms.rule.remove("smoke_dev")' | Out-Null
Expect-True -Label "dev_condition on: fired multiple times despite cooldown=999, sustain=999" `
  -Code 'return _G._smoke.fires >= 2'
Expect-True -Label "dev_condition: pure dev fires do NOT update last_fire_time" `
  -Code 'return _G._smoke.h.last_fire_time == nil'

Write-Host "==> manual fire bypasses condition"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_manual", {
    type      = sms.rule.TYPE.CONTINUOUS,
    interval  = 5,
    condition = function() return false end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Expect-True -Label "manual fire returns true on success" -Code 'return _G._smoke.h:fire()'
Expect-Eq -Label "manual fire ran the action" -Code 'return _G._smoke.fires' -Expected 1
Invoke-Smoke -Code 'sms.rule.remove("smoke_manual")' | Out-Null

Write-Host "==> name collision replaces old rule"
Invoke-Smoke -Code @"
  _G._smoke = {marker_a = 0, marker_b = 0}
  _G._smoke.a = sms.rule("smoke_collide", {
    type=sms.rule.TYPE.CONTINUOUS, interval=1,
    condition=function() return true end,
    action=function() _G._smoke.marker_a = _G._smoke.marker_a + 1 end,
  })
  _G._smoke.b = sms.rule("smoke_collide", {
    type=sms.rule.TYPE.CONTINUOUS, interval=1,
    condition=function() return true end,
    action=function() _G._smoke.marker_b = _G._smoke.marker_b + 1 end,
  })
"@ | Out-Null
Start-Sleep -Seconds 2
Invoke-Smoke -Code 'sms.rule.remove("smoke_collide")' | Out-Null
Expect-Eq -Label "collide: replaced rule did not fire after being replaced" -Code 'return _G._smoke.marker_a' -Expected 0
Expect-True -Label "collide: replacing rule fired" -Code 'return _G._smoke.marker_b >= 1'

Write-Host "==> registry: get / all / remove"
Invoke-Smoke -Code @"
  sms.rule("reg_a", {type=sms.rule.TYPE.CONTINUOUS, interval=1, condition=function()end, action=function()end})
  sms.rule("reg_b", {type=sms.rule.TYPE.CONTINUOUS, interval=1, condition=function()end, action=function()end})
"@ | Out-Null
Expect-True -Label "registry: get returns the handle" -Code 'return sms.rule.get("reg_a") ~= nil'
Expect-True -Label "registry: get on missing returns nil" -Code 'return sms.rule.get("not_there") == nil'
Expect-True -Label "registry: all returns at least 2 handles" -Code 'return #sms.rule.all() >= 2'
Expect-True -Label "registry: remove returns true on success" -Code 'return sms.rule.remove("reg_a")'
Expect-True -Label "registry: remove returns false on missing" -Code 'return sms.rule.remove("reg_a") == false'
Invoke-Smoke -Code 'sms.rule.remove("reg_b")' | Out-Null

Write-Host "==> test_all does not change rule state"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_test_all", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 5,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
  sms.rule.test_all()
"@ | Out-Null
Expect-Eq -Label "test_all: action ran (so fires == 1) but..." -Code 'return _G._smoke.fires' -Expected 1
Expect-True -Label "test_all: ONCE rule was NOT unregistered" -Code 'return sms.rule._rules["smoke_test_all"] ~= nil'
Expect-True -Label "test_all: last_fire_time was NOT set" `
  -Code 'return sms.rule._rules["smoke_test_all"].last_fire_time == nil'
Invoke-Smoke -Code 'sms.rule.remove("smoke_test_all")' | Out-Null

Write-Host "==> action throws are caught and don't unregister ONCE"
Invoke-Smoke -Code @"
  _G._smoke = {attempts = 0}
  _G._smoke.h = sms.rule("smoke_throw", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    condition = function() return true end,
    action    = function()
      _G._smoke.attempts = _G._smoke.attempts + 1
      error("boom from smoke_throw")
    end,
  })
"@ | Out-Null
Start-Sleep -Seconds 3
Invoke-Smoke -Code 'sms.rule.remove("smoke_throw")' | Out-Null
Expect-True -Label "throw: action retried (attempts >= 2)" -Code 'return _G._smoke.attempts >= 2'

Write-Host "==> :stop is idempotent"
Invoke-Smoke -Code @"
  _G._smoke = {h = sms.rule("smoke_stop", {
    type=sms.rule.TYPE.CONTINUOUS, interval=1,
    condition=function() return false end,
    action=function() end,
  })}
"@ | Out-Null
Expect-True -Label "stop: returns true when active" -Code 'return _G._smoke.h:stop()'
Expect-True -Label "stop: returns false when already stopped" -Code 'return _G._smoke.h:stop() == false'

Write-Host "==> :reset clears toggle active and cooldown bookkeeping"
Invoke-Smoke -Code @"
  _G._smoke = {fires = 0, on = false}
  _G._smoke.h = sms.rule("smoke_reset", {
    type      = sms.rule.TYPE.TOGGLE,
    interval  = 1,
    cooldown  = 30,
    condition = function() return _G._smoke.on end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
"@ | Out-Null
Invoke-Smoke -Code '_G._smoke.on = true' | Out-Null
Start-Sleep -Seconds 2
Expect-Eq -Label "reset: fired once" -Code 'return _G._smoke.fires' -Expected 1
Invoke-Smoke -Code '_G._smoke.h:reset()' | Out-Null
Start-Sleep -Seconds 2
Expect-Eq -Label "reset: refired on next tick after reset (cooldown cleared)" -Code 'return _G._smoke.fires' -Expected 2
Invoke-Smoke -Code 'sms.rule.remove("smoke_reset")' | Out-Null

Write-Host "==> verify [sms.rule] log lines for bad args and user errors"
Expect-LogContains -Label 'log: unknown type'        -Pattern 'type must be one of sms.rule.TYPE' -Grep '\[sms.rule\]'
Expect-LogContains -Label 'log: cooldown on ONCE'    -Pattern 'cooldown is meaningless on ONCE'   -Grep '\[sms.rule\]'
Expect-LogContains -Label 'log: action threw'        -Pattern 'boom from smoke_throw'             -Grep '\[sms.rule\]'
Expect-LogContains -Label 'log: manual fire'         -Pattern 'manual fire'                       -Grep '\[sms.rule\]'
Expect-LogContains -Label 'log: name collision'      -Pattern "replacing existing rule 'smoke_collide'" -Grep '\[sms.rule\]'

Write-SmokeSummary
