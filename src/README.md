# safeguard-bash Developer Guide
Bash script development can be done many ways, this is just one way in a linux terminal.

### Requirements
* Install [jq](https://stedolan.github.io/jq/manual/), this is not mandatory, but it is not installed by default and the user experience is better if installed.

* Clone this repository

### Installation
After cloning this repository, run the `install-local.sh` script. This will copy the relevant scripts to `$HOME/scripts`, 
and add that directory to your `$PATH` environment variable. After editing any of the scripts in the src directory simply 
run `install-local.sh` and test your changes.
