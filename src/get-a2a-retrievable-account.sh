#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-retrievable-account.sh [-h]
       get-a2a-retrievable-account.sh [-a appliance] [-B cabundle] [-v version] [-c file] [-k file] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -c  File containing client certificate
  -k  File containing client private key
  -p  Read certificate password from stdin

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
PassStdin=
Pass=

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

while getopts ":a:B:v:c:k:A:prh" opt; do
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
    p)
        PassStdin="-p"
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

Registrations=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "NONE" core GET "A2ARegistrations" $Version "")
echo $Registrations | jq -r '.[] | [.Id, .AppName, .Description // "", .Disabled, .CertificateUserId, .CertificateUser, .CertificateUserThumbPrint] | @tsv' |
    tr '\t' '|' | # when using \t in IFS the delimiters get aggregated and it doesn't recognize empty tokens
    while IFS='|' read -r RegId AppName RegDesc RegDisabled CertUserId CertUser CertThumbprint; do
        invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "NONE" core GET "A2ARegistrations/$RegId/RetrievableAccounts" $Version "" |
            jq .[] |
            jq --arg AppName "$AppName" --arg RegDesc "$RegDesc" --arg CertUserId "$CertUserId" --arg CertUser "$CertUser" --arg CertThumbprint "$CertThumbprint" \
                    '. + {AppName: $AppName, Description: $RegDesc, CertificateUserId: ($CertUserId | tonumber), CertificateUser: $CertUser, CertificateUserThumbprint: $CertThumbprint}'
    done | jq -S --arg RegDisabled "$RegDisabled" '. + {Disabled: (.AccountDisabled != 0 and $RegDisabled)} | del(.AccountDisabled)' | jq --slurp # slurp puts things back into an array


# echo $Registrations | jq . > /dev/null 2>&1
# if [ $? -ne 0 ]; then
#     echo $Registrations
# else
#     echo $Registrations | jq
# fi
