#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-retrievable-account.sh [-h]
       get-a2a-retrievable-account.sh [-a appliance] [-B cabundle] [-v version] [-c file] [-k file] [-p]
                                      [-q filter] [-f fields] [-o orderby]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -c  File containing client certificate
  -k  File containing client private key
  -p  Read certificate password from stdin
  -q  Query filter to pass to the API (SCIM-style, e.g. "AccountName eq 'root'")
  -f  Comma-separated list of fields to return (e.g. AccountName,AccountId)
  -o  Comma-separated list of fields to order by (e.g. AccountName)

List which accounts are retrievable by this certificate user via the Safeguard A2A service.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires jq for parsing and manipulating responses."
    exit 1
fi

Appliance=
CABundleArg=
CABundle=
Version=4
Cert=
PKey=
ApiKey=
Raw=false
Pass=
Filter=
Fields=
OrderBy=

. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/a2a.sh"

require_args()
{
    handle_ca_bundle_arg
    if [ -z "$Appliance" ]; then
        read -p "Appliance Network Address: " Appliance
    fi
    if [ -z "$Cert" ]; then
        read -p "Client Certificate File: " Cert
    fi
    if [ -z "$PKey" ]; then
        read -p "Client Private Key File: " PKey
    fi
    if [ -z "$Pass" ]; then
        read -s -p "Private Key Password: " Pass
        >&2 echo
    fi
}

while getopts ":a:B:v:c:k:A:q:f:o:prh" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    B)
        CABundle=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    c)
        Cert=$OPTARG
        ;;
    k)
        PKey=$OPTARG
        ;;
    q)
        Filter=$OPTARG
        ;;
    f)
        Fields=$OPTARG
        ;;
    o)
        OrderBy=$OPTARG
        ;;
    p)
        # -p: read cert password from stdin (handled by require_args)
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

# Build query parameters for the RetrievableAccounts endpoint
QueryParams=""
if [ -n "$Filter" ]; then
    QueryParams="filter=$(printf '%s' "$Filter" | sed 's/ /%20/g')"
fi
if [ -n "$Fields" ]; then
    [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
    QueryParams="${QueryParams}fields=$Fields"
fi
if [ -n "$OrderBy" ]; then
    [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
    QueryParams="${QueryParams}orderby=$OrderBy"
fi

if [[ $Version -eq 4 ]]; then
    ATTRRENAMEFILTER="jq .[]"
else
    ATTRRENAMEFILTER="jq '.[] | . + {AssetId: .SystemId, AssetName: .SystemName, AssetDescription: .SystemDescription} | delpaths([[\"SystemId\"], [\"SystemName\"], [\"SystemDescription\"]])'"
fi
Registrations=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "NONE" core GET "A2ARegistrations" $Version "")
echo "$Registrations" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    >&2 echo "$Registrations"
    exit 1
fi
echo $Registrations | jq -r '.[] | [.Id, .AppName, .Description // "", .Disabled, .CertificateUserId, .CertificateUser, .CertificateUserThumbPrint] | @tsv' |
    tr '\t' '|' |
    while IFS='|' read -r RegId AppName RegDesc RegDisabled CertUserId CertUser CertThumbprint; do
        Relurl="A2ARegistrations/$RegId/RetrievableAccounts"
        if [ -n "$QueryParams" ]; then
            Relurl="${Relurl}?${QueryParams}"
        fi
        invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "NONE" core GET "$Relurl" $Version "" |
            eval $ATTRRENAMEFILTER |
            jq -S --arg AppName "$AppName" --arg RegDesc "$RegDesc" --arg CertUserId "$CertUserId" --arg CertUser "$CertUser" --arg CertThumbprint "$CertThumbprint" --argjson RegDisabled "${RegDisabled:-false}" \
                    '. + {AppName: $AppName, Description: $RegDesc, CertificateUserId: ($CertUserId | tonumber), CertificateUser: $CertUser, CertificateUserThumbprint: $CertThumbprint, Disabled: ((.AccountDisabled // 0) != 0 and $RegDisabled)} | del(.AccountDisabled)'
    done | jq --slurp # slurp puts things back into an array


# echo $Registrations | jq . > /dev/null 2>&1
# if [ $? -ne 0 ]; then
#     echo $Registrations
# else
#     echo $Registrations | jq
# fi
