#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cp -R $ScriptDir/src/* $HOME/scripts
