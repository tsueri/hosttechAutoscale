#!/bin/bash

echo "Enter your User ID and your API Token and get a list of available Servers on your hosttech.cloud"
read -p "Please enter your USER_UUID as found on https://hosttech.cloud/Easy/APIs/: " USER_UUID
read -p "Please enter your API-Token as found on https://hosttech.cloud/Easy/APIs/: " API_TOKEN

USER_UUID=96761224-d36c-4615-86b1-73dff67301b7
API_TOKEN=8c21bbeecbf4a8d3073ca088cda1a743a6bc22493ff5905252458e0151203caf

serversjson=$(curl -H "Content-Type: application/json" \
-H "X-Auth-UserId: $USER_UUID" \
-H "X-Auth-Token: $API_TOKEN" \
-X GET \
https://api.hosttech.cloud/objects/servers)

echo $serversjson | jq '.[] | .[] | "\(.name) \(.object_uuid)" ' | tr -d "\"" | column -t -s' '
