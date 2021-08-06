#!/bin/bash

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires the jq utility for parsing JSON response data from Safeguard"
    exit 1
fi

# This script is made to be passed as a generic handler to handle-event.sh

# Notice that handle-event.sh passes four lines of data to the handler script:
#  - line 1 has the appliance address
#  - line 2 has the access token currently in use
#  - line 3 has the path to the CA bundle file to use for trusted connections
#  - line 4 has the event data JSON minified to a single line of output

# This is just for adding color output to the terminal--it makes it easier to read
# The YELLOW and NC variables contain control characters that when echoed will switch
# the terminal output color to yellow or normal color respectively.
if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# This section of the file reads four lines of data from handle-event.sh. In your
# integration project you will need these lines in your script to read the data
# passed in by handle-event.sh.
#
# The '-t 0.5' prevents this script from hanging on a read operation should
# something go wrong.
read -t 0.5 Appliance
read -t 0.5 AccessToken
read -t 0.5 CABundle
read -t 0.5 EventData

# This sample script just prints out the values that were received from handle-event.sh.
# Your script would do something much more useful with this data.
echo -e "${YELLOW}$0 received Appliance:${NC} $Appliance"
echo -e "${YELLOW}$0 received AccessToken:${NC} $AccessToken"
echo -e "${YELLOW}$0 received CABundle file:${NC} $CABundle"
echo -e "${YELLOW}$0 received the following object...${NC}"
echo $EventData | jq .

# The Appliance and AccessToken variables (along with CABundle) can be used to call
# invoke-safeguard-method.sh to take action on the information in EventData.
#
# The best way to do this is to call invoke-safeguard-method.sh using the -T option
# to avoid exposing the access token. For example (replace ... with your options):
#
# invoke-safeguard-method.sh -a $Appliance -B $CABundle -T ... <<<$AccessToken

