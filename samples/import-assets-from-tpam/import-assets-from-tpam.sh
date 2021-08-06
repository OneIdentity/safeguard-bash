#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: import-assets-from-tpam.sh [-h]
       import-assets-from-tpam.sh [-a appliance] [-t accesstoken] [-T tpam_appliance] [-I tpam_cli_ssh_key] [-P asset_partition_id]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -T  Network address of the TPAM appliance
  -I  SSH key for TPAM CLI access
  -P  ID of asset partition to put new assets

Download all TPAM systems and import them into Safeguard.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

set -e

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SgBashDir="$(dirname $(which connect-safeguard.sh))"

. "$SgBashDir/utils/loginfile.sh"

# This script is meant to be run from within a fresh safeguard-bash Docker container
if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

Appliance=
AccessToken=
Tpam=
TpamKey=
PartitionId=-1

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

while getopts ":t:a:T:I:P:h" opt; do
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
    P)
        PartitionId=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

if [ -z "$(which jq 2> /dev/null)" ]; then
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
\"Linux\": $($SgBashDir/get-platform.sh -n 'Other Linux Other' | jq .[].Id),
\"Windows Desktop\": $($SgBashDir/get-platform.sh -n 'Windows Other' | jq .[].Id),
\"Windows\": $($SgBashDir/get-platform.sh -n 'Windows Other' | jq .[].Id),
\"MacOSX\": $($SgBashDir/get-platform.sh -n 'OS X Other' | jq .[].Id),
\"AIX\": $($SgBashDir/get-platform.sh -n 'AIX Other' | jq .[].Id),
\"HP-UX\": $($SgBashDir/get-platform.sh -n 'HP-UX Other' | jq .[].Id)
}"
PlatformFilter="select( $(echo $PlatformMapping | jq -r 'to_entries[] | "(.PlatformId | contains(\"" + .key +  "\")) or"' | tr '\n' ' ' | sed 's/...$//'))"

migrate_platform_id()
{
    SgRemoved=$(echo $1 | jq ".[] | $PlatformFilter" | jq -s .)
    >&2 echo -e "${YELLOW}Found platform matches for $(echo $SgRemoved | jq '. | length') records${NC}"
    echo $SgRemoved | jq --argjson mapping "$PlatformMapping" '.[] | with_entries(
           if (.key == "PlatformId") then
               .value |= (. as $val | ($mapping | to_entries[] | select(.key == $val) | .value))
           else . end )
           ' | jq -s .
}

>&2 echo -e "${YELLOW}Fetching systems from TPAM...${NC}"
Output=$(ssh -i $TpamKey -oStrictHostKeyChecking=no $Tpam ListSystems -MaxRows 0)
TpamJson=$(while read -r OutputLine; do echo "$OutputLine" | sed 's/\r//' | jq -R 'split("\t")'; done <<< "$Output" | jq -s -f "$ScriptDir/csv2json-helper.jq")
TpamJsonFiltered=$(echo $TpamJson \
           | jq '.[] | {SystemName,NetworkAddress,PlatformName,PortNumber,Description}' \
           | jq ". + { \"AssetPartitionId\": $PartitionId }" | jq -s .)
SgJsonPre=$(echo $TpamJsonFiltered \
           | jq '.[] | with_entries(
                 if (.key == "SystemName") then
                     .key |= "Name"
                 elif (.key == "PortNumber") then
                     .key |= "ConnectionProperties"
                 elif (.key == "PlatformName") then
                     .key |= "PlatformId"
                 else . end )' \
           | jq 'with_entries(
                 if ((.key == "ConnectionProperties") and (.value == null)) then
                     .value |= { ServiceAccountCredentialType: "None" }
                 elif (.key == "ConnectionProperties") then
                     .value |= { ServiceAccountCredentialType: "None", Port: . }
                 else . end )' | jq -s .)
>&2 echo -e "${YELLOW}Found $(echo $SgJsonPre | jq '. | length') records${NC}"
SgJson=$(migrate_platform_id "$SgJsonPre")

>&2 echo -e "${YELLOW}Adding new records to Safeguard...${NC}"
invoke-safeguard-method.sh -a "$Appliance" -t "$AccessToken" -s core -m POST -U "Assets/Batch" -N -b "$SgJson"

