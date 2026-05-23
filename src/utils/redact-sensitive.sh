#!/bin/bash
# src/utils/redact-sensitive.sh
#
# Narrow, allowlist-only redaction of SDK auth-plumbing secrets in error
# output. Intended to be called immediately before echoing captured curl
# stderr / response bodies to the user's stderr stream when a request fails.
#
# This helper implements the D-013 "redaction-scope doctrine" recorded in
# E:\source\OpenSource\security-triage.md: it redacts only the SDK's own
# bearer/access/refresh/id tokens and a small fixed set of HTTP header
# values that carry transport-layer secrets. It MUST NOT touch product
# response fields like Password, ApiKey, PrivateKey, PasswordRulesPolicyId,
# ApiKeyName, RequirePasswordChange, PasswordHistoryDepth, etc. -- those
# are legitimate Safeguard API payload data and the SDK does not get to
# decide what the caller logs.
#
# Field-name matching is EXACT case-insensitive equality on the allowlist.
# Substring or partial matching is a defect: see Test 5 in
# test/suites/suite-security-cred-redaction.sh.
#
# Usage:
#   echo "$captured_text" | redact_sensitive
#   redact_sensitive < some_file
#
# Sources the helper, then calls the function. Not intended to be invoked
# as an external command.

# Allowlist of JSON keys whose values get masked. Case-insensitive EXACT
# match on the key name -- no substring, no regex glob.
_REDACT_JSON_KEYS=(
    "AccessToken"
    "access_token"
    "refresh_token"
    "id_token"
    "UserToken"
)

# Allowlist of HTTP header names whose values get masked when the input
# contains raw header lines (e.g. curl -v output, openssl s_client trace).
_REDACT_HEADERS=(
    "Authorization"
    "Cookie"
    "Set-Cookie"
)

_REDACT_MASK='***REDACTED***'

# Build a single ERE alternation from the allowlist, used by both the jq
# fallback and the sed fallback. Keys are matched case-insensitively via
# the (?i)-equivalent character classes built per-letter.
_redact_build_key_alternation()
{
    local key alt=""
    for key in "${_REDACT_JSON_KEYS[@]}"; do
        if [ -n "$alt" ]; then
            alt="$alt|"
        fi
        alt="${alt}${key}"
    done
    printf '%s' "$alt"
}

_redact_build_header_alternation()
{
    local hdr alt=""
    for hdr in "${_REDACT_HEADERS[@]}"; do
        if [ -n "$alt" ]; then
            alt="$alt|"
        fi
        alt="${alt}${hdr}"
    done
    printf '%s' "$alt"
}

# Internal: sed-only redaction. Used both as the no-jq fallback and as the
# HTTP-header pass that runs regardless of jq availability.
_redact_with_sed()
{
    local input="$1"
    local json_alt header_alt
    json_alt=$(_redact_build_key_alternation)
    header_alt=$(_redact_build_header_alternation)

    # JSON-key redaction:
    #   "AccessToken":"..."     -> "AccessToken":"***REDACTED***"
    #   "AccessToken" : "..."   -> "AccessToken" : "***REDACTED***"
    # Anchored on the literal key name surrounded by JSON double-quotes
    # and followed by ':' so that field names whose JSON-key spelling
    # merely *contains* an allowlist substring (e.g. "AccessTokenLifetime",
    # "ApiKeyName") are NOT matched. The key name itself is exact.
    #
    # sed -E does not support (?i); we generate a [Aa][Cc]... character
    # class per letter so the match is case-insensitive.
    local ci_json_alt
    ci_json_alt=$(printf '%s' "$json_alt" | awk '
        BEGIN { RS="|"; ORS="|" }
        {
            out=""
            n = length($0)
            for (i = 1; i <= n; i++) {
                c = substr($0, i, 1)
                u = toupper(c); l = tolower(c)
                if (u == l) { out = out c }
                else        { out = out "[" u l "]" }
            }
            print out
        }
    ' | sed 's/|$//')

    local ci_header_alt
    ci_header_alt=$(printf '%s' "$header_alt" | awk '
        BEGIN { RS="|"; ORS="|" }
        {
            out=""
            n = length($0)
            for (i = 1; i <= n; i++) {
                c = substr($0, i, 1)
                u = toupper(c); l = tolower(c)
                if (u == l) { out = out c }
                else        { out = out "[" u l "]" }
            }
            print out
        }
    ' | sed 's/|$//')

    # JSON string values: "<Key>" : "<value>"
    # (Numeric or boolean values are not produced for token fields in
    # Safeguard's API surface, so we only handle the string form.)
    printf '%s' "$input" | sed -E "
        s/(\"(${ci_json_alt})\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1${_REDACT_MASK}\3/g
        s/^([[:space:]]*[<>*][[:space:]]+)?(${ci_header_alt}):[[:space:]]*.*$/\1\2: ${_REDACT_MASK}/I
    "
}

# Internal: jq-based redaction. Only runs if the input parses as JSON.
# Walks the entire object tree and replaces any key whose lowercased name
# is in the allowlist. Exact equality on the (lowercased) key name -- no
# substring, no glob.
_redact_with_jq()
{
    local input="$1"
    local jq_filter
    jq_filter=$(cat <<'JQ'
def redact_keys($keys; $mask):
    walk(
        if type == "object" then
            with_entries(
                if ($keys | index(.key | ascii_downcase)) then
                    .value = $mask
                else . end
            )
        else . end
    );
. as $orig
| (try (redact_keys($keys; $mask)) catch $orig)
JQ
)
    local keys_json
    keys_json=$(printf '%s\n' "${_REDACT_JSON_KEYS[@]}" \
        | tr '[:upper:]' '[:lower:]' \
        | jq -R . | jq -s .)

    printf '%s' "$input" | jq \
        --argjson keys "$keys_json" \
        --arg mask "$_REDACT_MASK" \
        "$jq_filter" 2>/dev/null
}

# Public entry point. Reads stdin (or the single positional argument),
# applies redaction, prints result on stdout.
redact_sensitive()
{
    local input
    if [ $# -ge 1 ]; then
        input="$1"
    else
        input=$(cat)
    fi

    if [ -z "$input" ]; then
        return 0
    fi

    local out=""
    # Prefer jq for the JSON pass when available and the input parses as
    # JSON. jq guarantees we will not damage JSON structure when the input
    # contains nested objects, arrays, escaped quotes, etc.
    if command -v jq >/dev/null 2>&1; then
        out=$(_redact_with_jq "$input")
    fi

    if [ -z "$out" ]; then
        # jq is missing OR the input was not valid JSON (e.g. it is a
        # curl trace, an openssl s_client error stream, or a mixed
        # text+JSON capture). Fall back to the line-oriented sed pass,
        # which handles both JSON key/value pairs that appear inline in
        # text and raw HTTP header lines.
        out=$(_redact_with_sed "$input")
    else
        # We have valid JSON output from jq, but it may have embedded
        # header lines or duplicate copies of the raw curl trace. Run
        # the header redaction over the jq output to catch those.
        out=$(_redact_with_sed "$out")
    fi

    printf '%s' "$out"
}

# write_pass_file VALUE
#
# Write VALUE into a mode-0600 temp file and echo the path. Used to keep
# passwords out of argv when shelling out to openssl s_client, which
# otherwise exposes -pass pass:VALUE in `ps -ef` output. The caller is
# responsible for arranging cleanup via trap or explicit rm -f.
write_pass_file()
{
    local _wpf_value="$1"
    local _wpf_path
    _wpf_path=$(mktemp 2>/dev/null) || _wpf_path="${TMPDIR:-/tmp}/.sg_pass.$$.$RANDOM"
    ( umask 0077 && printf '%s' "$_wpf_value" > "$_wpf_path" ) || return 1
    chmod 0600 "$_wpf_path" 2>/dev/null || true
    printf '%s' "$_wpf_path"
}