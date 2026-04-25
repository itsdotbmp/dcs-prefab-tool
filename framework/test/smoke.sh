#!/usr/bin/env bash
# End-to-end smoke test for the dcs-sms framework v1 (logger + utils).
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework/sms.lua"
"${DCSSMS}" exec --file sms.lua >/dev/null

echo "==> load framework/log.lua"
"${DCSSMS}" exec --file log.lua >/dev/null

echo "==> load framework/utils.lua"
"${DCSSMS}" exec --file utils.lua >/dev/null

echo "==> sms.utils.add_numbers(2, 3) should return 5"
result=$("${DCSSMS}" exec --code "return sms.utils.add_numbers(2, 3)")
echo "${result}"
echo "${result}" | grep -q '"return_value":5' \
  || { echo "FAIL: expected return_value:5, got: ${result}"; exit 1; }

echo "==> sms.log.info('hello from smoke test')"
"${DCSSMS}" exec --code "sms.log.info('hello from smoke test')" >/dev/null

echo "==> sms.log.error('boom from smoke test')"
"${DCSSMS}" exec --code "sms.log.error('boom from smoke test')" >/dev/null

echo "==> verify dcs.log captured tagged lines"
log_window=$("${DCSSMS}" tail-log --grep '\[sms' -n 200)

echo "${log_window}" | grep -q '\[sms.utils\] add_numbers(2, 3)' \
  || { echo "FAIL: missing [sms.utils] add_numbers line in dcs.log"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q '\[sms\] hello from smoke test' \
  || { echo "FAIL: missing [sms] hello line in dcs.log"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q '\[sms\] boom from smoke test' \
  || { echo "FAIL: missing [sms] boom line in dcs.log"; echo "${log_window}"; exit 1; }

echo "smoke ok"
