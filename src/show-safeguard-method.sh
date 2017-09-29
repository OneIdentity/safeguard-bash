#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: show-safeguard-method.sh [-h]
       show-safeguard-method.sh [-a appliance] [-v version] [-s service] [-m method] [-U relativeurl]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -s  Service: core, appliance, cluster, notification
  -m  HTTP Method: GET, PUT, POST, DELETE
  -U  Relative resource URL (e.g. AccessRequests)

Call Swagger endpoint to retrieve API documentation and provide API guidance. This script
will help you know what to send to the invoke-safeguard-method.sh script.

This script requires jq for processing JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Version=2
Service=
Method=
RelativeUrl=
Accept="application/json"
ContentType="application/json"
FilterNulls=true

. "$ScriptDir/utils/loginfile.sh"

Appliance=$(read_from_login_file Appliance)

require_args()
{
    if [ -z "$Appliance" ]; then
        read -p "Appliance network address: " Appliance
    fi
    if [ -z "$Service" ]; then
        read -p "Service [core,appliance,cluster,notification]: " Service
    fi
    Service=$(echo "$Service" | tr '[:upper:]' '[:lower:]')
    case $Service in
        core|appliance|cluster|notification) ;;
        *) >&2 echo "Must specify a valid Safeguard service name!"; print_usage ;;
    esac
    if [ ! -z "$Method" ]; then
        Method=$(echo "$Method" | tr '[:lower:]' '[:upper:]')
        case $Method in
            GET|PUT|POST|DELETE) ;;
            *) >&2 echo "Must specify a valid HTTP method!"; print_usage ;;
        esac
    fi
    if ! [[ $Version =~ ^[0-9]+$ ]]; then
        >&2 echo "Version must be a number!"; print_usage
    fi
}

while getopts ":a:v:s:m:U:h" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    s)
        Service=$OPTARG
        ;;
    m)
        Method=$OPTARG
        ;;
    U)
        RelativeUrl=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires extensive JSON parsing, so you must download and install jq to use it."
    exit 1
fi

require_args

Url="https://$Appliance/service/$Service/swagger/docs/v$Version"
Swagger=$(curl -s -k -X GET -H "Accept: $Accept" $Url)
Paths=$(echo $Swagger | jq '.paths')
Definitions=$(echo $Swagger | jq '.definitions')

# Special definition of brand new jq function
#   Eventually when this is mainstream you would want to remove this and use walk()
read -r -d '' MyWalk <<EOF
def my_walk(f):
  . as \$in
  | if type == "object" then
      reduce keys_unsorted[] as \$key
        ( {}; . + { (\$key):  (\$in[\$key] | my_walk(f)) } ) | f
  elif type == "array" then map( my_walk(f) ) | f
  else f
  end;
EOF

unroll_definitions()
{
    local OldObj=$1
    local LoopInvariant=$(echo $OldObj | jq '.. | select(type == "object" or type == "array") | to_entries | map(
        select(.value? | type == "string" and startswith("#/definitions/"))) | select(.[0]? != null)' | jq -s 'map(.[])')
    if [ -z "$LoopInvariant" -o "$LoopInvariant" = "null" -o "$LoopInvariant" = "[]" ]; then
        echo $OldObj
    else
        local DefEntry=$(echo $LoopInvariant | jq '.[0]?')
        local DefKey=$(echo $DefEntry | jq -r '.key?')
        local DefValue=$(echo $DefEntry | jq -r '.value?')
        local DefName=$(echo $DefEntry | jq -r '.value? | ltrimstr("#/definitions/")')
        local DefEntity=$(echo $Definitions | jq "to_entries[] | select(.key == \"$DefName\") | .value")
        local DefType=$(echo $DefEntity | jq  -r '.type?')
        if [ "$DefType" = "enum" ]; then
            local DefResolved=$(echo $Definitions | jq "to_entries[] | select(.key == \"$DefName\") | .value | \"ENUM \(.title): \(.enum | join(\", \"))\"")
        else
            local DefResolved=$(echo $Definitions | jq "to_entries[] | select(.key == \"$DefName\") | .value.properties | with_entries(
                if (.value | has(\"enum\")) then
                    .value |= .[\"\$ref\"]
                elif (.value.type == \"array\") then
                    if (.value.items | has(\"enum\")) then
                        .value |= [\"ENUM: \(.items.enum |join(\", \"))\"]
                    else
                        .value |= [.items.\"\$ref\"]
                    end
                elif (.value | has(\"\$ref\")) then
                    .value |= .[\"\$ref\"]
                else
                    .value |= .description
                end
            )")
        fi
        local NewObj=$(echo $OldObj | jq --argjson resolved "$DefResolved" "$MyWalk my_walk(
			if (type == \"object\" and has(\"$DefKey\")) then
				.[\"$DefKey\"] |= \$resolved
			elif (type == \"array\" and .[0]? == \"$DefValue\") then
                .[0] |= \$resolved
            else
				.
			end)")
        echo $(unroll_definitions "$NewObj")
    fi
}

if [ ! -z "$RelativeUrl" -a ! -z "$Method" ]; then
    PathFilter="to_entries[] | select(.key == \"/v$Version/$RelativeUrl\")"
elif [ ! -z "$RelativeUrl" ]; then
    PathFilter="to_entries[] | select(.key | startswith(\"/v$Version/$RelativeUrl\"))"
else
    PathFilter='to_entries[]'
fi

if [ ! -z "$RelativeUrl" -a ! -z "$Method" ]; then
    Ops=$(echo $Paths | jq "$PathFilter")
    MethodFilter=$(echo "$Method" | tr '[:upper:]' '[:lower:]')
    MethodExists=$(echo $Ops | jq -r ".value.$MethodFilter")
    if [ -z "$MethodExists" -o "$MethodExists" = "null" ]; then
        >&2 echo "Method $Method not found for relative path '$RelativeUrl'"
        exit 1
    fi
    BodyObj=$(echo $Ops | jq ".value.$MethodFilter.parameters[] | select(.in == \"body\") | .schema")
    BodyType=$(echo $BodyObj | jq -r '.type')
    if [ "$BodyType" = "array" ]; then
        Body=$(echo $BodyObj | jq "[.items[]]")
    else
        Body=$(echo $BodyObj | jq ".[]")
    fi
    if [ -z "$Body" ]; then
        Body='null'
    fi
    Obj=$(echo $Ops | jq "{ 
        \"Path\": .key | ltrimstr(\"/v$Version/\"), 
        \"Method\": \"$Method\", 
        \"Description\": .value.$MethodFilter.summary,
        \"QueryParameters\": [.value.$MethodFilter.parameters[] | select(.in == \"query\") | {
            \"Name\": .name,
            \"Description\": .description,
            \"Type\": .type,
            \"Required\": .required 
        }],
        \"PathParameters\": [.value.$MethodFilter.parameters[] | select(.in == \"path\") | {
            \"Name\": .name,
            \"Description\": .description,
            \"Type\": .type,
            \"Required\": .required
        }],
        \"Body\": $Body
    }")
    echo $(unroll_definitions "$Obj") | jq .
else
    PathPrinter="$PathFilter | \"\\(.key | ltrimstr(\"/v$Version/\"));\\(.value | keys | join(\", \") | ascii_upcase)\""
    Results=$(echo $Paths | jq -r "$PathPrinter" | column -s\; -t)
    if [ -z "$Results" ]; then
        >&2 echo "Unable to find endpoint with relative url '$RelativeUrl'"
        exit 1
    fi
    echo $Paths | jq -r "$PathPrinter" | column -s\; -t
fi

