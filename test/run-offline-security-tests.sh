#!/bin/bash
# test/run-offline-security-tests.sh
#
# Offline-only runner for the suite-security-* suites. Skips any test that
# requires a live appliance (those gate on $TestAppliance non-empty). Used
# during S5 implementation and S6 review when an appliance is unavailable
# or held by a concurrent agent.
#
# Usage:
#   ./test/run-offline-security-tests.sh             # all security suites
#   ./test/run-offline-security-tests.sh redaction   # filter by substring

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$ScriptDir/framework.sh"

# Initialise context with no appliance -- live cases will sg_skip.
init_test_context "" "" "" 4

SuiteDir="$ScriptDir/suites"
Filter="$1"

SuiteFiles=()
for f in "$SuiteDir"/suite-security-*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$Filter" ]; then
        case "$(basename "$f")" in
            *"$Filter"*) ;;
            *) continue ;;
        esac
    fi
    SuiteFiles+=("$f")
done

if [ ${#SuiteFiles[@]} -eq 0 ]; then
    echo "No matching security suites found."
    exit 0
fi

echo "============================================"
echo "  safeguard-bash offline security test run"
echo "  (live-appliance cases will be SKIPped)"
echo "============================================"

for suite_file in "${SuiteFiles[@]}"; do
    run_suite "$suite_file"
done

print_test_report
exit $_TotalFail
