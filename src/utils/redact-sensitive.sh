#!/bin/bash
# src/utils/redact-sensitive.sh
#
# Shared utility for passing secrets to openssl without exposing them in
# process listings.

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
