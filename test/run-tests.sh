#!/bin/bash
# safeguard-bash test runner
# Discovers and runs test suites against a live Safeguard appliance.

print_usage()
{
    cat <<EOF
USAGE: run-tests.sh [-h]
       run-tests.sh -a <appliance> -u <user> -p <password> [-v version] [-s suite]

  -h  Show help and exit
  -a  Network address of the Safeguard appliance
  -u  Admin username (e.g. Admin)
  -p  Admin password
  -v  API version (default: 4)
  -s  Run only the specified suite (substring match on filename, may be repeated)

EXAMPLES:
  # Run all suites
  ./test/run-tests.sh -a 10.5.32.162 -u Admin -p MyPassword

  # Run only the connect suite
  ./test/run-tests.sh -a 10.5.32.162 -u Admin -p MyPassword -s connect

  # Run with v3 API
  ./test/run-tests.sh -a 10.5.32.162 -u Admin -p MyPassword -v 3

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
User=
Password=
Version=4
SuiteFilters=()

while getopts ":a:u:p:v:s:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    u) User=$OPTARG ;;
    p) Password=$OPTARG ;;
    v) Version=$OPTARG ;;
    s) SuiteFilters+=("$OPTARG") ;;
    h) print_usage ;;
    esac
done

# Validate required arguments
if [ -z "$Appliance" ] || [ -z "$User" ] || [ -z "$Password" ]; then
    >&2 echo "Error: -a appliance, -u user, and -p password are required."
    >&2 echo "Run with -h for usage information."
    exit 1
fi

# Check for required tools
for tool in curl jq; do
    if [ -z "$(which $tool 2>/dev/null)" ]; then
        >&2 echo "Error: $tool is required but not found."
        exit 1
    fi
done

# Source the test framework
. "$ScriptDir/framework.sh"

# Initialize context
init_test_context "$Appliance" "$User" "$Password" "$Version"

echo "============================================"
echo "  safeguard-bash test runner"
echo "============================================"
echo "  Appliance: $TestAppliance"
echo "  User:      $TestUser"
echo "  Version:   v$TestVersion"
echo "============================================"

# Discover suites
SuiteDir="$ScriptDir/suites"
if [ ! -d "$SuiteDir" ]; then
    >&2 echo "Error: Suite directory not found: $SuiteDir"
    exit 1
fi

SuiteFiles=()
for f in "$SuiteDir"/suite-*.sh; do
    [ -f "$f" ] || continue

    # Apply suite filter if specified
    if [ ${#SuiteFilters[@]} -gt 0 ]; then
        matched=false
        for filter in "${SuiteFilters[@]}"; do
            if echo "$(basename "$f")" | grep -qi "$filter"; then
                matched=true
                break
            fi
        done
        if [ "$matched" = false ]; then
            continue
        fi
    fi

    SuiteFiles+=("$f")
done

if [ ${#SuiteFiles[@]} -eq 0 ]; then
    echo "No matching test suites found."
    exit 0
fi

echo "Found ${#SuiteFiles[@]} suite(s) to run."

# --- Ensure Resource Owner Grant is enabled ---
# Connect via PKCE first (works regardless of ROG state), check the
# appliance grant-type setting, enable ROG if needed, then disconnect
# so individual suites start with a clean session.
echo ""
echo "Connecting via PKCE to check Resource Owner grant type..."
sg_connect_pkce
if [ ! -f "$HOME/.safeguard_login" ]; then
    >&2 echo "Error: PKCE connection failed. Cannot proceed."
    exit 1
fi

sg_ensure_rog_enabled
sg_disconnect

# Guarantee ROG is restored on exit (even if tests fail or are interrupted)
trap sg_restore_rog EXIT

# Run each suite
for suite_file in "${SuiteFiles[@]}"; do
    run_suite "$suite_file"
done

# Print report and exit
print_test_report
exit $_TotalFail
