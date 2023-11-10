#!/usr/bin/env bash

set -e
set +v
set +x

VORIPOS_PROVISION_VERSION=0.4.0
VORI_API_ROOT="${VORI_API_ROOT:-https://api.vori.com/v1}"

Normal=$(tput sgr0)
Italic=$(tput sitm)
Red=$(tput setaf 1)
Green=$(tput setaf 2)
Yellow=$(tput setaf 3)

# Get provisioning token from the user
# NOTE: We will make this visible for now (hence, no -s) to make training and debugging simpler.
read -p "$(echo -e $Yellow"Please input the provisioning token: "$Normal)" provisioningToken

# Check if token is valid
echo "Validating token..."
response=$(curl --silent -w "\n%{http_code}" -L -X POST $VORI_API_ROOT"/lane-provisioning-tokens/metadata" -H "Content-Type: application/json" -H "X-Vori-Voripos-Provision-Version: $VORIPOS_PROVISION_VERSION" -d '{"token": "'$provisioningToken'"}')

# Parse the response
statusCode=$(tail -n1 <<< "$response")  # Get the status code from the last line
content=$(sed '$ d' <<< "$response")   # Get everything except the last line (which contains the status code)

if (( statusCode > 299 )); then
    echo -e $Red"Token validation failed!"
    echo -e $content$Normal
    exit 1
fi

environment=$( jq -r  '.environment | select( . != null )' <<< "${content}" )
bannerID=$( jq -r  '.banner.id | select( . != null )' <<< "${content}" )
bannerName=$( jq -r  '.banner.name | select( . != null )' <<< "${content}" )
storeID=$( jq -r  '.store.id | select( . != null )' <<< "${content}" )
storeName=$( jq -r  '.store.name | select( . != null )' <<< "${content}" )
laneID=$( jq -r  '.lane.id | select( . != null )' <<< "${content}" )
laneName=$( jq -r  '.lane.name | select( . != null )' <<< "${content}" )

echo -e $Green"Successfully validated token."$Normal
printf "%15s %s\n" "Environment" "$environment"
printf "%15s %s\n" "Banner ID" "$bannerID"
printf "%15s %s\n" "Banner Name" "$bannerName"
printf "%15s %s\n" "Store ID" "$storeID"
printf "%15s %s\n" "Store Name" "$storeName"
printf "%15s %s\n" "Lane ID" "$laneID"
printf "%15s %b\n" "Lane Name" "${laneName:-$Yellow$Italic(Not set)$Normal}"

# The user must explicitly agree to continue provisioning
read -p "$(echo -e $Yellow"Do you want to provision this machine with the above details? This will store credentials on this machine. The token will be consumed and no longer be usable. Type 'yes' if you want to provision: "$Normal)" reply

if [ $reply != "yes" ]; then
    echo "Provisioning cancelled."
    exit 1
fi

echo "Retrieving credentials from Vori..."
response=$(curl --silent -w "\n%{http_code}" -L -X POST $VORI_API_ROOT"/lane-provisioning-tokens/exchange" -H "Content-Type: application/json" -H "X-Vori-Voripos-Provision-Version: $VORIPOS_PROVISION_VERSION" -d '{"token": "'$provisioningToken'"}')

# Parse the response
statusCode=$(tail -n1 <<< "$response")  # Get the status code from the last line
content=$(sed '$ d' <<< "$response")   # Get everything except the last line (which contains the status code)

environment=$( jq -r  '.metadata.environment | select( . != null )' <<< "${content}" )
bannerID=$( jq -r  '.metadata.banner.id | select( . != null )' <<< "${content}" )
bannerName=$( jq -r  '.metadata.banner.name | select( . != null )' <<< "${content}" )
storeID=$( jq -r  '.metadata.store.id | select( . != null )' <<< "${content}" )
storeName=$( jq -r  '.metadata.store.name | select( . != null )' <<< "${content}" )
laneID=$( jq -r  '.metadata.lane.id | select( . != null )' <<< "${content}" )
laneName=$( jq -r  '.metadata.lane.name | select( . != null )' <<< "${content}" )
datacapMerchantID=$( jq -r  '.datacap_merchant_id | select( . != null )' <<< "${content}" )
orderIdPrefix=$( jq -r  '.order_id_prefix | select( . != null )' <<< "${content}" )
litefsCloudToken=$( jq -r  '.litefs_cloud_token | select( . != null )' <<< "${content}" )
txnDbBucket=$( jq -r  '.transaction_bucket | select( . != null )' <<< "${content}" )
transactionKey=$( jq -r  '.transaction_key | select( . != null )' <<< "${content}" )
otlpHostname=$( jq -r  '.otlp.hostname | select( . != null )' <<< "${content}" )
otlpPort=$( jq -r  '.otlp.port | select( . != null )' <<< "${content}" )
otlpUsername=$( jq -r  '.otlp.auth.basic.username | select( . != null )' <<< "${content}" )
otlpPassword=$( jq -r  '.otlp.auth.basic.password | select( . != null )' <<< "${content}" )

echo "Storing credentials..."
mkdir -p "$HOME/voripos"
txnKeyPath="$HOME/voripos/gcp.json"
echo "$transactionKey" | base64 --decode > "$txnKeyPath"

# Metadata
defaults write com.vori.VoriPOS provisioned_environment -string "$environment"
defaults write com.vori.VoriPOS provisioned_bannerID -string "$bannerID"
defaults write com.vori.VoriPOS provisioned_bannerName -string "$bannerName"
defaults write com.vori.VoriPOS provisioned_storeID -string "$storeID"
defaults write com.vori.VoriPOS provisioned_storeName -string "$storeName"
defaults write com.vori.VoriPOS provisioned_laneID -string "$laneID"
defaults write com.vori.VoriPOS provisioned_laneName -string "$laneName"

# Payments
defaults write com.vori.VoriPOS provisioned_datacapMerchantID -string "$datacapMerchantID"

# Receipts
defaults write com.vori.VoriPOS provisioned_orderPrefix -string "$orderIdPrefix"

# Data sync
defaults write com.vori.VoriPOS provisioned_litefsCloudToken -string "$litefsCloudToken"
defaults write com.vori.VoriPOS provisioned_txnDbBucket -string "$txnDbBucket"
defaults write com.vori.VoriPOS provisioned_txnKeyPath -string "$txnKeyPath"

# OpenTelemetry (OTLP)
defaults write com.vori.VoriPOS provisioned_otlpHostname -string "$otlpHostname"
defaults write com.vori.VoriPOS provisioned_otlpPort -integer "$otlpPort"
defaults write com.vori.VoriPOS provisioned_otlpUsername -string "$otlpUsername"
defaults write com.vori.VoriPOS provisioned_otlpPassword -string "$otlpPassword"

echo "Starting background services..."
brew services restart voripos-otel-collector
brew services restart voripos-domain-sync
brew services restart voripos-txn-sync
echo
echo "Sync services started. You may need to wait up to five minutes for the initial domain data sync if this is a new installation. See the LiteFS container logs in Docker Desktop for status."
echo
echo -e $Green"VoriPOS provisioning was successful! Restart the app (if it's running) to reload the latest configuration."$Normal
