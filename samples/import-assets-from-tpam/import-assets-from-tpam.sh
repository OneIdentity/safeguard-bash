#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: import-assets-from-tpam.sh [-h]
       import-assets-from-tpam.sh [-a appliance] [-t accesstoken] [-T tpam_appliance] [-I tpam_cli_ssh_key]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -T  Network address of the TPAM appliance
  -I  SSH key for TPAM CLI access

Download all TPAM systems and import them into Safeguard.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SgBashDir="$(dirname $(which connect-safeguard.sh))"

. "$SgBashDir/utils/loginfile.sh"

Appliance=
AccessToken=
Tpam=
TpamKey=

require_args()
{
    require_login_args
    if [ -z "$Tpam" ]; then
        read -p "Tpam network address: " Tpam
    fi
    if [ -z "$TpamKey" ]; then
        read -p "Tpam CLI SSH key file path: " TpamKey
    fi
}

while getopts ":t:a:T:I:h" opt; do
    case $opt in
    t)
        AccessToken=$OPTARG
        ;;
    a)
        Appliance=$OPTARG
        ;;
    T)
        Tpam=$OPTARG
        ;;
    I)
        TpamKey=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires extensive JSON parsing, so you must download and install jq to use it."
    exit 1
fi
if [ -z "$(which sed)" ]; then
    >&2 echo "This script requires special parsing, so you must download and install sed to use it."
    exit 1
fi

require_args

# this could easily be extended--it makes sense to use "Other" versions
PlatformMapping="{
\"Linux\": \"$($SgBashDir/get-platform.sh 'Other Linux Other')\",
\"Windows Desktop\": \"$($SgBashDir/get-platform.sh 'Windows Other')\",
\"Windows\": \"$($SgBashDir/get-platform.sh 'Windows Other')\",
\"MacOSX\": \"$($SgBashDir/get-platform.sh 'OS X Other')\",
\"AIX\": \"$($SgBashDir/get-platform.sh 'AIX Other')\",
\"HP-UX\": \"$($SgBashDir/get-platform.sh 'HP-UX Other')\"
}"

PlatformFilter="select( $(echo $PlatformMapping | jq -r 'to_entries[] | "(.PlatformId | has(\"" + .key +  "\")) or"' | tr '\n' ' ' | sed 's/...$//'))"

echo "PlatformFilter=$PlatformFilter"

migrate_platform_id()
{
    echo $1 | jq "$PlatformFilter" 
}

>&2 echo "Fetching systems from TPAM..."
Output=$(ssh -i $TpamKey $Tpam ListSystems -MaxRows 0)
TpamJson=$(while read -r OutputLine; do echo "$OutputLine" | sed 's/\r//' | jq -R 'split("\t")'; done <<< "$Output" | jq -s -f "$ScriptDir/csv2json-helper.jq")
TpamJsonFiltered=$(echo $TpamJson \
           | jq '.[] | {SystemName,NetworkAddress,PlatformName,PortNumber,Description}' | jq -s .)
SgJsonPre=$(echo $TpamJsonFiltered \
           | jq '.[] | with_entries(
                 if (.key == "SystemName") then
                     .key |= "Name" 
                 elif (.key == "PortNumber") then
                     .key |= "ConnectionProperties"
                 elif (.key == "PlatformName") then
                     .key |= "PlatformId" else . end )' \
           | jq 'with_entries(
                 if ((.key == "ConnectionProperties") and (.value == null)) then
                     .value |= { ServiceAccountCredentialType: "None" } 
                 elif (.key == "ConnectionProperties") then
                     .value |= { ServiceAccountCredentialType: "None", Port: .value }
                 else . end )' | jq -s .)
>&2 echo "Found $(echo $SgJsonPre | jq '. | length') records"
SgJson=$(migrate_platform_id $SgJsonPre)
