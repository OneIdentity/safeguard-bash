#! /bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-appliance-status.sh [-h] [-a appliance] [-v version]
  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default

Anonymously retrieve the appliance status.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}


ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Version=2

while getopts ":a:v:h" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

$ScriptDir/invoke-safeguard-method.sh -n -a "$Appliance" -s notification -v $Version -m GET -U SystemVerification/Manufacturing

