#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: set-a2a-password.sh [-h]
       set-a2a-password.sh [-a appliance] [-B cabundle] [-v version] [-c file] [-k file] [-A apikey] [-O] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -O  Use openssl s_client instead of curl for TLS client authentication problems
  -p  Read certificate password from stdin

Set an account password using the Safeguard A2A service (bidirectional). The new
password is read from stdin (after any certificate password). The A2A registration
must have bidirectional enabled.

Requires a certificate-authenticated A2A registration with bidirectional support.

EXAMPLES:
  # Set password interactively (prompts for cert password, then new password)
  set-a2a-password.sh -a 10.5.32.54 -c cert.pem -k key.pem -A <apikey>

  # Set password non-interactively (passwordless key)
  echo "" | set-a2a-password.sh -a 10.5.32.54 -c cert.pem -k key.pem -A <apikey> -p <<< '"NewPass1!"'

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundleArg=
CABundle=
Version=4
Cert=
PKey=
ApiKey=
Pass=
UseOpenSslSclient=false

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
    if [ -z "$ApiKey" ]; then
        read -p "A2A API Key: " ApiKey
    fi
}

while getopts ":a:B:v:c:k:A:pOh" opt; do
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
        # -p: read cert password from stdin (handled by require_args)
        ;;
    A)
        ApiKey=$OPTARG
        ;;
    O)
        UseOpenSslSclient=true
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

# Read the new password from stdin
read -r NewPassword
if [ -z "$NewPassword" ]; then
    >&2 echo "Error: No new password provided on stdin."
    exit 1
fi

# Ensure the password is a valid JSON string (wrap in quotes if not already)
if ! echo "$NewPassword" | jq -e . >/dev/null 2>&1; then
    NewPassword=$(printf '%s' "$NewPassword" | jq -Rs .)
fi

ERRORFILTER='cat'
if [ ! -z "$(which jq 2> /dev/null)" ]; then
    ERRORFILTER='jq .'
fi

Result=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "$ApiKey" a2a PUT "Credentials/Password" $Version $UseOpenSslSclient "$NewPassword")
if [ -n "$Result" ]; then
    echo $Result | jq . > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo $Result
    else
        Error=$(echo $Result | jq .Code 2> /dev/null)
        if [ -z "$Error" -o "$Error" = "null" ]; then
            echo $Result | $ERRORFILTER
        else
            echo $Result | $ERRORFILTER
            exit 1
        fi
    fi
fi
