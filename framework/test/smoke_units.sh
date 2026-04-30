#!/usr/bin/env bash
# End-to-end smoke test for sms.units and sms.statics catalogs.
# Verifies the catalogs load cleanly and resolve a representative subset
# of well-known type strings, plus origin_of behavior for base / pack /
# unknown / non-string inputs.
#
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.
# (No spawning is performed — this is a pure-string-equality smoke.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers
expect_eq_string() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
  echo "PASS: ${label}"
}

expect_nil() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":null' \
    || { echo "FAIL: ${label} (expected null): ${result}"; exit 1; }
  echo "PASS: ${label}"
}

# Reload the framework once so we know we're testing the just-built version.
"${DCSSMS}" exec --file load_all.lua >/dev/null

# Spot-checks for sms.units across each top-level bucket.
expect_eq_string "planes.F_16C_50"           "return sms.units.planes.F_16C_50"             "F-16C_50"
expect_eq_string "helicopters.AH_64D"        "return sms.units.helicopters.AH_64D"          "AH-64D"
expect_eq_string "armor.tanks.T_72B"         "return sms.units.armor.tanks.T_72B"           "T-72B"
expect_eq_string "armor.ifv.BMP_2"           "return sms.units.armor.ifv.BMP_2"             "BMP-2"
expect_eq_string "armor.apc.BTR_80"          "return sms.units.armor.apc.BTR_80"            "BTR-80"
expect_eq_string "artillery.M_109"           "return sms.units.artillery.M_109"             "M-109"
expect_eq_string "infantry.Soldier_M4"       "return sms.units.infantry.Soldier_M4"         "Soldier M4"
expect_eq_string "ships.warships.MOSCOW"     "return sms.units.ships.warships.MOSCOW"       "MOSCOW"

# Bunker was routed into sms.units.fortifications by Task 9's routing fix.
expect_eq_string "units.fortifications.Bunker" "return sms.units.fortifications.Bunker"     "Bunker"

# sms.statics spot-checks (entries that actually exist in the generated catalog).
expect_eq_string "statics.animals.Cow"       "return sms.statics.animals.Cow"               "Cow"
expect_eq_string "statics.heliports.FARP"    "return sms.statics.heliports.FARP"            "FARP"

# origin_of: base game
expect_nil "origin_of base F-16C_50"     "return sms.units.origin_of('F-16C_50')"

# origin_of: asset pack (Cold War — T-80B is a CWAP tank)
expect_eq_string "origin_of T-80B"       "return sms.units.origin_of('T-80B')"          "Cold War Asset Pack"

# origin_of: unknown / non-string (silent nil)
expect_nil "origin_of unknown"           "return sms.units.origin_of('definitely-not-a-type')"
expect_nil "origin_of nil"               "return sms.units.origin_of(nil)"
expect_nil "origin_of number"            "return sms.units.origin_of(42)"

echo
echo "ALL smoke_units checks passed."
