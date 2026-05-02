# End-to-end smoke test for sms.K.units and sms.K.statics catalogs.
# Verifies the catalogs load cleanly and resolve a representative subset
# of well-known type strings, plus origin_of behavior for base / pack /
# unknown / non-string inputs.
#
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.
# (No spawning is performed — this is a pure-string-equality smoke.)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Reload the framework once so we know we're testing the just-built version.
Invoke-Smoke -File 'load_all.lua' | Out-Null

# Spot-checks for sms.K.units across each top-level bucket.
Expect-EqString -Label 'planes.F_16C_50'           -Code 'return sms.K.units.planes.F_16C_50'             -Expected 'F-16C_50'
Expect-EqString -Label 'helicopters.AH_64D'        -Code 'return sms.K.units.helicopters.AH_64D'          -Expected 'AH-64D'
Expect-EqString -Label 'armor.tanks.T_72B'         -Code 'return sms.K.units.armor.tanks.T_72B'           -Expected 'T-72B'
Expect-EqString -Label 'armor.ifv.BMP_2'           -Code 'return sms.K.units.armor.ifv.BMP_2'             -Expected 'BMP-2'
Expect-EqString -Label 'armor.apc.BTR_80'          -Code 'return sms.K.units.armor.apc.BTR_80'            -Expected 'BTR-80'
Expect-EqString -Label 'artillery.M_109'           -Code 'return sms.K.units.artillery.M_109'             -Expected 'M-109'
Expect-EqString -Label 'infantry.Soldier_M4'       -Code 'return sms.K.units.infantry.Soldier_M4'         -Expected 'Soldier M4'
Expect-EqString -Label 'ships.warships.MOSCOW'     -Code 'return sms.K.units.ships.warships.MOSCOW'       -Expected 'MOSCOW'

# Bunker was routed into sms.K.units.fortifications by Task 9's routing fix.
Expect-EqString -Label 'units.fortifications.Bunker' -Code 'return sms.K.units.fortifications.Bunker'    -Expected 'Bunker'

# sms.K.statics spot-checks (entries that actually exist in the generated catalog).
Expect-EqString -Label 'statics.animals.Cow'       -Code 'return sms.K.statics.animals.Cow'               -Expected 'Cow'
Expect-EqString -Label 'statics.heliports.FARP'    -Code 'return sms.K.statics.heliports.FARP'            -Expected 'FARP'

# origin_of: base game
Expect-Nil -Label 'origin_of base F-16C_50' -Code "return sms.K.units.origin_of('F-16C_50')"

# origin_of: asset pack (Cold War — T-80B is a CWAP tank)
Expect-EqString -Label 'origin_of T-80B' -Code "return sms.K.units.origin_of('T-80B')" -Expected 'Cold War Asset Pack'

# origin_of: unknown / non-string (silent nil)
Expect-Nil -Label 'origin_of unknown' -Code "return sms.K.units.origin_of('definitely-not-a-type')"
Expect-Nil -Label 'origin_of nil'     -Code 'return sms.K.units.origin_of(nil)'
Expect-Nil -Label 'origin_of number'  -Code 'return sms.K.units.origin_of(42)'

Write-Host ""
Write-Host "ALL smoke_units checks passed."
