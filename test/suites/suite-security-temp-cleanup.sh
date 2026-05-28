#!/bin/bash
# test/suites/suite-security-temp-cleanup.sh
#
# Regression suite for temp-file cleanup.
#
# Asserts that helpers which write secrets or response bytes to disk:
#   - use mktemp (or equivalent random-suffix paths), not predictable .$$
#   - create the file mode-0600
#   - register cleanup so the file is removed when the function returns
#
# These tests are offline -- they exercise the write_pass_file helper and
# inspect a2a.sh's source for the absence of predictable .$$ paths. They
# do not require a live appliance.

suite_name() { echo "security-temp-cleanup"; }

suite_setup()
{
    : # nothing to set up
}

suite_cleanup()
{
    : # nothing to tear down
}

suite_execute()
{
    local script_dir before after pf
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    # Test 1: write_pass_file creates a file with mode 0600.
    . "$script_dir/src/utils/redact-sensitive.sh"
    pf=$(write_pass_file "hunter2-test-pass")
    sg_assert "Test 1 write_pass_file returned a path" [ -n "$pf" ]
    sg_assert "Test 1 write_pass_file path exists" [ -f "$pf" ]
    if command -v stat >/dev/null 2>&1; then
        local mode os
        mode=$(stat -c '%a' "$pf" 2>/dev/null) || mode=$(stat -f '%Lp' "$pf" 2>/dev/null)
        os=$(uname -o 2>/dev/null || uname -s 2>/dev/null)
        case "$os" in
            Msys|Cygwin|MINGW*|MSYS*|CYGWIN*)
                sg_skip "Test 1 chmod mode check (NTFS does not honor POSIX modes on $os)"
                ;;
            *)
                if [ -n "$mode" ]; then
                    sg_assert_equal "Test 1 write_pass_file mode is 0600" "$mode" "600"
                else
                    sg_skip "Test 1 stat unavailable for mode check"
                fi
                ;;
        esac
    else
        sg_skip "Test 1 stat unavailable for mode check"
    fi

    # Test 2: contents round-trip exactly.
    local content
    content=$(cat "$pf")
    sg_assert_equal "Test 2 write_pass_file wrote exact value" "hunter2-test-pass" "$content"

    rm -f "$pf"

    # Test 3: two consecutive write_pass_file calls yield distinct paths
    # (i.e. the suffix is randomized, not just $$).
    local p1 p2
    p1=$(write_pass_file "a")
    p2=$(write_pass_file "b")
    sg_assert "Test 3 two write_pass_file calls return different paths" \
        [ "$p1" != "$p2" ]
    rm -f "$p1" "$p2"

    # Test 4: src/utils/a2a.sh primary path uses mktemp (not bare .$$).
    # A fallback "${TMPDIR:-/tmp}/.a2a_*.$$.$RANDOM" is acceptable -- it is
    # gated on mktemp(1) being unavailable, and the $RANDOM suffix removes
    # the predictability of bare-$$ naming.
    if grep -E -q 'CurlErrFile=\$\(mktemp' "$script_dir/src/utils/a2a.sh" \
       && grep -E -q 'SclientErrFile=\$\(mktemp' "$script_dir/src/utils/a2a.sh"; then
        sg_assert "Test 4 a2a.sh assigns CurlErrFile and SclientErrFile via mktemp" true
    else
        sg_assert "Test 4 a2a.sh assigns CurlErrFile and SclientErrFile via mktemp" false
    fi

    # Test 4b: there must be no bare .a2a_*err.$$ reference (no $RANDOM
    # suffix, no mktemp). grep for the bare token followed by " or end of
    # line -- catches the pre-fix predictable naming.
    if grep -E -q '\.a2a_(curl|sclient)_err\.\$\$["[:space:]]' \
        "$script_dir/src/utils/a2a.sh"; then
        sg_assert "Test 4b a2a.sh has no bare .\$\$ temp filename references" false
    else
        sg_assert "Test 4b a2a.sh has no bare .\$\$ temp filename references" true
    fi

    # Test 5: a2a.sh actually uses mktemp.
    if grep -q 'mktemp' "$script_dir/src/utils/a2a.sh"; then
        sg_assert "Test 5 a2a.sh uses mktemp" true
    else
        sg_assert "Test 5 a2a.sh uses mktemp" false
    fi

    # Test 6: a2a.sh registers a trap for cleanup of the temp files.
    if grep -E -q 'trap[^#]*rm -f.*(CurlErrFile|SclientErrFile|PassFile)' \
        "$script_dir/src/utils/a2a.sh"; then
        sg_assert "Test 6 a2a.sh installs a trap to remove temp files" true
    else
        sg_assert "Test 6 a2a.sh installs a trap to remove temp files" false
    fi
}
