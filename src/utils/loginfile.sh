#!/bin/bash
# This is a script to support login files across multiple scripts
# It shouldn't be called directly.

LoginFile="$HOME/.safeguard_login"

read_from_login_file()
{
    cat $LoginFile | grep $1 | cut -d \= -f 2
}

use_login_file()
{
    if ! [[ -r "$LoginFile" && -f "$LoginFile" ]]; then
        $ScriptDir/connect-safeguard.sh
    fi
    Appliance=$(read_from_login_file Appliance)
    Provider=$(read_from_login_file Provider)
    AccessToken=$(read_from_login_file AccessToken)
    if [ "$Provider" = "certificate" ]; then
        Cert=$(read_from_login_file Cert)
        PKey=$(read_from_login_file PKey)
    fi
}

require_login_args()
{
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

