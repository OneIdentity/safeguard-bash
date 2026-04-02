#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-asset.sh [-h]
       new-asset.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                    [-n displayname] [-N networkaddress] [-P platformid] [-D description]
                    [-d partitionid] [-p port]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -n  Display name for the asset (required)
  -N  Network address (IP or hostname) of the asset (required)
  -P  Platform ID (required, e.g. 521 for Linux, 547 for Windows Server)
  -D  Description
  -d  Asset partition ID (default: -1 for Default Partition)
  -p  Port number for connection

Use get-platform.sh to find the platform ID for your asset type.

Requires AssetAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
DisplayName=
NetworkAddress=
PlatformId=
Description=
PartitionId=-1
Port=

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:n:N:P:D:d:p:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    n) DisplayName=$OPTARG ;;
    N) NetworkAddress=$OPTARG ;;
    P) PlatformId=$OPTARG ;;
    D) Description=$OPTARG ;;
    d) PartitionId=$OPTARG ;;
    p) Port=$OPTARG ;;
    h) print_usage ;;
    esac
done

if [ -z "$DisplayName" ]; then
    >&2 echo "Error: -n displayname is required."
    exit 1
fi

if [ -z "$NetworkAddress" ]; then
    >&2 echo "Error: -N networkaddress is required."
    exit 1
fi

if [ -z "$PlatformId" ]; then
    >&2 echo "Error: -P platformid is required."
    exit 1
fi

require_login_args

Body=$(jq -n \
    --arg name "$DisplayName" \
    --arg addr "$NetworkAddress" \
    --argjson plat "$PlatformId" \
    --argjson part "$PartitionId" \
    '{
        Name: $name,
        NetworkAddress: $addr,
        PlatformId: $plat,
        AssetPartitionId: $part,
        ConnectionProperties: {
            ServiceAccountCredentialType: "None"
        }
    }')

if [ -n "$Description" ]; then
    Body=$(echo "$Body" | jq --arg desc "$Description" '.Description = $desc')
fi

if [ -n "$Port" ]; then
    Body=$(echo "$Body" | jq --argjson port "$Port" '.ConnectionProperties.Port = $port')
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m POST -U "Assets" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error creating asset:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
