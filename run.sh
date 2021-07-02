#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_usage()
{
    cat <<EOF
USAGE: run.sh [-v volume] [-h] [-c command]

  -h  Show help and exit
  -v  Directory from host to mount into container at /volume
      This is useful for mounting a directory with certificates and private keys
  -c  Alternate command to run in the container (often -c bash to get a prompt)
      Always specify the -c option last

EOF
    exit 0
}

while getopts ":v:h" opt; do
    case $opt in
    v)
        Volume=$OPTARG
        shift; shift;
        ;;
    h)
        print_usage
        ;;
    ?)
        break
        ;;
    esac
done

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

if [ ! -z "$(which docker)" ]; then
    docker images | grep safeguard-bash
    if [ $? -ne 0 ]; then
        $ScriptDir/build.sh
    fi
    echo -e "${YELLOW}Running the oneidentity/safeguard-bash container.\n" \
            "You can specify an alternate startup command using arguments to this script.\n" \
            "The default entrypoint is bash, so use the -c argument.\n" \
            "  e.g. run.sh -c /bin/bash${NC}"
    if [ -z "$Volume" ]; then
        docker run -it oneidentity/safeguard-bash "$@"
    else
        docker run -v "$Volume:/volume" -it oneidentity/safeguard-bash "$@"
    fi
else
    >&2 echo "You must install docker to use this script"
fi

