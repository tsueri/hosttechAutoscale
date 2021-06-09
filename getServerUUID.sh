#!/bin/bash

if ! command -v jq >/dev/null; then
  read -p "This script requires jq to be installed and on your PATH. Would you like to install jq now? (Y/N)" answer
    if [[ "$answer" == "y" || "$answer" == "Y"  ]]; then
      sudo apt update && sudo apt install -y jq
    else
      echo "jq is reqiered. Exit now."
      exit 1
    fi
fi

echo "Enter your User ID and your API Token and get a list of available Servers on your hosttech.cloud"
read -p "Please enter your USER_UUID as found on https://hosttech.cloud/Easy/APIs/: " USER_UUID
read -p "Please enter your API-Token as found on https://hosttech.cloud/Easy/APIs/: " API_TOKEN

serversjson=$(curl -H "Content-Type: application/json" \
-H "X-Auth-UserId: $USER_UUID" \
-H "X-Auth-Token: $API_TOKEN" \
-X GET \
https://api.hosttech.cloud/objects/servers)

echo $serversjson | jq '.[] | .[] | "\(.name) \(.object_uuid)" ' | tr -d "\"" | column -t -s' '
