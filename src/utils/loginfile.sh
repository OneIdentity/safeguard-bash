#!/bin/bash
# This is a script to support login files across multiple scripts
# It shouldn't be called directly.

LoginFile="$HOME/.safeguard_login"

read_from_login_file()
{
    cat $LoginFile | grep $1 | cut -d \= -f 2
}

handle_ca_bundle_arg()
{
    if [ -z "$CABundleArg" ]; then
        if [ -z "$CABundle" ]; then
            CABundleArg="-k"
        else
            CABundleArg="--cacert $CABundle"
        fi
    fi
}

use_login_file()
{
    if ! [[ -r "$LoginFile" && -f "$LoginFile" ]]; then
        $ScriptDir/connect-safeguard.sh
    fi
    Appliance=$(read_from_login_file Appliance)
    Provider=$(read_from_login_file Provider)
    AccessToken=$(read_from_login_file AccessToken)
    CABundleArg=$(read_from_login_file CABundleArg)
    if [ "$Provider" = "certificate" ]; then
        Cert=$(read_from_login_file Cert)
        PKey=$(read_from_login_file PKey)
    fi
}

require_login_args()
{
    handle_ca_bundle_arg
    if [[ -z "$Appliance" && -z "$AccessToken" ]]; then
        use_login_file
    else
        if [ -z "$Appliance" ]; then
            read -p "Appliance network address: " Appliance
        fi
        if [ -z "$AccessToken" ]; then
            AccessToken=$($ScriptDir/connect-safeguard.sh -a $Appliance -X)
        fi
    fi
}

query_providers()
{
    if [ ! -z "$(which jq)" ]; then
        GetPrimaryProvidersRelativeURL="RSTS/UserLogin/LoginController?response_type=token&redirect_uri=urn:InstalledApplication&loginRequestStep=1"
        # certificate provider not returned by default because it is marked as not supporting HTML forms login
        Providers=$(curl -s $CABundleArg -X POST -H "Accept: application/x-www-form-urlencoded" "https://$Appliance/$GetPrimaryProvidersRelativeURL" \
                         -d 'RelayState=' | jq '.Providers|.[].Id' | xargs echo -n)
        if [ -z "$Providers" ]; then
            >&2 echo "Unable to obtain list of identity providers, does $Appliance exist?"
            exit 1
        fi
        Providers=$(echo certificate $Providers)
    fi
}

require_connect_args()
{
    handle_ca_bundle_arg
    if [ -z "$Appliance" ]; then
        read -p "Appliance Network Address: " Appliance
    fi
    if $QueryProviders; then
        if [ ! -z "$(which jq)" ]; then
            query_providers
        else
            >&2 echo "You must install jq to query providers"
            exit 1
        fi
    fi
    if [ -z "$Provider" ]; then
        if [ ! -z "$Providers" ]; then
            read -p "Identity Provider ($Providers): " Provider
        else
            read -p "Identity Provider: " Provider
        fi
    fi
    if [ ! -z "$Providers" ]; then
        if ! [[ $Providers =~ (^|[[:space:]])$Provider($|[[:space:]]) ]]; then
            >&2 echo "Specified provider '$Provider' must be one of: $Providers!"; print_usage
        fi
    fi
    if [ "$Provider" = "certificate" ]; then
        if [ -z "$Cert" ]; then
            read -p "Client Certificate File: " Cert
        fi
        if [ -z "$PKey" ]; then
            read -p "Client Private Key File: " PKey
        fi
        local CertResolved=$(readlink -f "$Cert")
        local PKeyResolved=$(readlink -f "$PKey")
        if [ ! -e "$CertResolved" ]; then
            >&2 echo "Client Certificate File '$Cert' does not exist"; print_usage
        fi
        if [ ! -e "$PKeyResolved" ]; then
            >&2 echo "Client Private Key File '$PKey' does not exist"; print_usage
        fi
        Cert=$CertResolved
        PKey=$PKeyResolved
    else
        if [ -z "$User" ]; then
            read -p "Username: " User
        fi
    fi
    if [ -z "$Pass" ]; then
        read -s -p "Password: " Pass
        >&2 echo
    fi
}

