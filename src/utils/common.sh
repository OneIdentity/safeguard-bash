#!/bin/bash
# This is a script to add common functionality across multiple scripts
# It shouldn't be called directly.

BackOffWait=1
backoff_wait()
{
    local WaitMax=30
    if [ ! -z "$1" ]; then
        WaitMax=$1
    fi
    sleep $BackOffWait
    if [ $BackOffWait -lt $WaitMax ]; then
        BackOffWait=$((BackOffWait+1))
    fi
}
reset_backoff_wait()
{
    BackOffWait=1
}

