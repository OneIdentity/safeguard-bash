#! /bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-appliance-status.sh [-h] [-a appliance] [-v version]
  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 4 is default

Anonymously retrieve the appliance status.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}


ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Version=4

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    if [ -z "Appliance" ]; then
        read -p "Appliance Network Address: " Appliance
    fi
}

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

if [ -z "$Appliance" ]; then
    if [[ -r "$LoginFile" && -f "$LoginFile" ]]; then
        Appliance=$(read_from_login_file Appliance)
    fi
fi

require_args

$ScriptDir/invoke-safeguard-method.sh -n -a "$Appliance" -s notification -v $Version -m GET -U Status

