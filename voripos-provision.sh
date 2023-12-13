#!/usr/bin/env bash

set -e
set +v
set +x

VORIPOS_PROVISION_VERSION=0.11.0
VORI_API_ROOT="${VORI_API_ROOT:-https://api.vori.com/v1}"
DOMAIN_FILE_PATH="${HOME}/Library/Containers/com.vori.VoriPOS/Data/Library/Application Support/Domain"

Normal=$(tput sgr0)
Italic=$(tput sitm)
Red=$(tput setaf 1)
Green=$(tput setaf 2)
Yellow=$(tput setaf 3)

downloadDomainDb=false
reprovision=false
silent=false
provisioningToken=''
accessToken=

while getopts 'drst:' OPTION; do
  case "$OPTION" in
    d)
      downloadDomainDb=true
      ;;
    r)
      reprovision=true
      ;;
    s)
      silent=true
      ;;
    t)
      provisioningToken="$OPTARG"
      ;;
    ?)
      echo "Usage: $(basename "$0") [-d] [-r] [-s] [-t token]" >&2
      exit 1
      ;;
  esac
done

# Ensure we can retrieve an access token if re-provisioning
if [ "$reprovision" = true ] ; then
  # NOTE: Read attempts will halt execution if the keys do not exist.
  oidcClientID=$(defaults read com.vori.VoriPOS provisioned_oidcClientID)
  oidcClientSecret=$(defaults read com.vori.VoriPOS provisioned_oidcClientSecret)
  oidcTokenUrl=$(defaults read com.vori.VoriPOS provisioned_oidcTokenUrl)

  response=$(curl --silent -w "\n%{http_code}" -L -X POST "$oidcTokenUrl" -u "$oidcClientID:$oidcClientSecret" -d "grant_type=client_credentials&scope=api" -H "X-Vori-Voripos-Provision-Version: $VORIPOS_PROVISION_VERSION")
  statusCode=$(tail -n1 <<< "$response")
  content=$(sed '$ d' <<< "$response")
  accessToken=$( jq -r  '.access_token | select( . != null )' <<< "${content}" )

  if [[ -z $accessToken ]]; then
    echo "Failed to retrieve access token (status=$statusCode): $content"
    exit 1
  fi
else
  # Always download the domain database on initial provision
  downloadDomainDb=true
fi

if [ "$silent" = true ] ; then
  if [[ -z $provisioningToken && "$reprovision" != true ]]; then
    echo 'Either set the re-provisioning flag, or set a provisioning token when using silent mode.'
    exit 1;
  fi
fi


if [[ -z $provisioningToken && "$reprovision" != true ]]; then
  # Get provisioning token from the user
  # NOTE: We will make this visible for now (hence, no -s) to make training and debugging simpler.
  read -r -p "$(echo -e "${Yellow}Please input the provisioning token: ${Normal}")" provisioningToken
else
    echo 'Using token from command line...'
fi

# These allow us to switch the cURL command args, depending on whether we are using OAuth.
declare -a curlArgs=()

if [[ -z $accessToken ]]; then
  curlArgs=('-d' "{\"token\": \"$provisioningToken\"}")
else
  curlArgs=('-H' "Authorization: Bearer $accessToken")
fi

# Check if token is valid
echo "Validating token..."
response=$(curl --silent -w "\n%{http_code}" -L -X POST "$VORI_API_ROOT/lane-provisioning-tokens/metadata" -H "Content-Type: application/json" -H "X-Vori-Voripos-Provision-Version: $VORIPOS_PROVISION_VERSION" "${curlArgs[@]}")

# Parse the response
statusCode=$(tail -n1 <<< "$response")  # Get the status code from the last line
content=$(sed '$ d' <<< "$response")   # Get everything except the last line (which contains the status code)

if (( statusCode > 299 )); then
    echo -e "${Red}Token validation failed!"
    echo -e "${content}${Normal}"
    exit 1
fi

environment=$( jq -r  '.environment | select( . != null )' <<< "${content}" )
bannerID=$( jq -r  '.banner.id | select( . != null )' <<< "${content}" )
bannerName=$( jq -r  '.banner.name | select( . != null )' <<< "${content}" )
storeID=$( jq -r  '.store.id | select( . != null )' <<< "${content}" )
storeName=$( jq -r  '.store.name | select( . != null )' <<< "${content}" )
laneID=$( jq -r  '.lane.id | select( . != null )' <<< "${content}" )
laneName=$( jq -r  '.lane.name | select( . != null )' <<< "${content}" )

echo -e "${Green}Successfully validated token.${Normal}"
printf "%15s %s\n" "Environment" "$environment"
printf "%15s %s\n" "Banner ID" "$bannerID"
printf "%15s %s\n" "Banner Name" "$bannerName"
printf "%15s %s\n" "Store ID" "$storeID"
printf "%15s %s\n" "Store Name" "$storeName"
printf "%15s %s\n" "Lane ID" "$laneID"
printf "%15s %b\n" "Lane Name" "${laneName:-$Yellow$Italic(Not set)$Normal}"

if [ "$silent" != true ] ; then
  # The user must explicitly agree to continue provisioning
  read -r -p "$(echo -e "${Yellow}Do you want to provision this machine with the above details? This will store credentials on this machine. The token will be consumed and no longer be usable. Type 'yes' if you want to provision: ${Normal}")" reply

  if [ "$reply" != "yes" ]; then
      echo "Provisioning cancelled."
      exit 1
  fi
fi

echo "Retrieving credentials from Vori..."
response=$(curl --silent -w "\n%{http_code}" -L -X POST "$VORI_API_ROOT/lane-provisioning-tokens/exchange" -H "Content-Type: application/json" -H "X-Vori-Voripos-Provision-Version: $VORIPOS_PROVISION_VERSION" "${curlArgs[@]}")

# Parse the response
statusCode=$(tail -n1 <<< "$response")  # Get the status code from the last line
content=$(sed '$ d' <<< "$response")   # Get everything except the last line (which contains the status code)

environment=$( jq -r  '.metadata.environment | select( . != null )' <<< "${content}" )
voriApiUrl=$( jq -r  '.vori_api_url | select( . != null )' <<< "${content}" )
bannerID=$( jq -r  '.metadata.banner.id | select( . != null )' <<< "${content}" )
bannerName=$( jq -r  '.metadata.banner.name | select( . != null )' <<< "${content}" )
storeID=$( jq -r  '.metadata.store.id | select( . != null )' <<< "${content}" )
storeName=$( jq -r  '.metadata.store.name | select( . != null )' <<< "${content}" )
laneID=$( jq -r  '.metadata.lane.id | select( . != null )' <<< "${content}" )
laneName=$( jq -r  '.metadata.lane.name | select( . != null )' <<< "${content}" )
datacapMerchantID=$( jq -r  '.datacap_merchant_id | select( . != null )' <<< "${content}" )
orderIdPrefix=$( jq -r  '.order_id_prefix | select( . != null )' <<< "${content}" )
litestreamType=$( jq -r  '.litestream_config.type | select( . != null )' <<< "${content}" )
litestreamEndpoint=$( jq -r  '.litestream_config.endpoint | select( . != null )' <<< "${content}" )
litestreamRegion=$( jq -r  '.litestream_config.region | select( . != null )' <<< "${content}" )
litestreamBucket=$( jq -r  '.litestream_config.bucket | select( . != null )' <<< "${content}" )
litestreamPath=$( jq -r  '.litestream_config.path | select( . != null )' <<< "${content}" )
oidcClientID=$( jq -r  '.oidc.client_id | select( . != null )' <<< "${content}" )
oidcClientSecret=$( jq -r  '.oidc.client_secret | select( . != null )' <<< "${content}" )
oidcTokenUrl=$( jq -r  '.oidc.token_url | select( . != null )' <<< "${content}" )
otlpHostname=$( jq -r  '.otlp.hostname | select( . != null )' <<< "${content}" )
otlpPort=$( jq -r  '.otlp.port | select( . != null )' <<< "${content}" )

echo "Storing credentials..."

defaults write com.vori.VoriPOS provisioned_voriApiUrl -string "$voriApiUrl"

# Metadata
defaults write com.vori.VoriPOS provisioned_environment -string "$environment"
defaults write com.vori.VoriPOS provisioned_bannerID -string "$bannerID"
defaults write com.vori.VoriPOS provisioned_bannerName -string "$bannerName"
defaults write com.vori.VoriPOS provisioned_storeID -string "$storeID"
defaults write com.vori.VoriPOS provisioned_storeName -string "$storeName"
defaults write com.vori.VoriPOS provisioned_laneID -string "$laneID"
defaults write com.vori.VoriPOS provisioned_laneName -string "$laneName"

# OIDC
defaults write com.vori.VoriPOS provisioned_oidcClientID -string "$oidcClientID"
defaults write com.vori.VoriPOS provisioned_oidcClientSecret -string "$oidcClientSecret"
defaults write com.vori.VoriPOS provisioned_oidcTokenUrl -string "$oidcTokenUrl"

# Payments
defaults write com.vori.VoriPOS provisioned_datacapMerchantID -string "$datacapMerchantID"

# Receipts
defaults write com.vori.VoriPOS provisioned_orderPrefix -string "$orderIdPrefix"

# OpenTelemetry (OTLP)
defaults write com.vori.VoriPOS provisioned_otlpHostname -string "$otlpHostname"
defaults write com.vori.VoriPOS provisioned_otlpPort -integer "$otlpPort"

# Transaction sync
defaults write com.vori.VoriPOS provisioned_litestreamType -string "$litestreamType"
defaults write com.vori.VoriPOS provisioned_litestreamEndpoint -string "$litestreamEndpoint"
defaults write com.vori.VoriPOS provisioned_litestreamRegion -string "$litestreamRegion"
defaults write com.vori.VoriPOS provisioned_litestreamBucket -string "$litestreamBucket"
defaults write com.vori.VoriPOS provisioned_litestreamPath -string "$litestreamPath"

# Download the domain database during the initial provisioning
if [ $downloadDomainDb = true ] ; then
  if [[ -z $accessToken ]]; then
    echo "Retrieving access token..."
    response=$(curl -X POST \
      "$oidcTokenUrl" \
      -H "Authorization: Basic $(echo -n "$oidcClientID:$oidcClientSecret" | base64)" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials&scope=api")
    content=$(sed '$ d' <<< "$response")
    accessToken=$( jq -r  '.access_token | select( . != null )' <<< "${content}" )
    curlArgs=('-H' "Authorization: Bearer $accessToken")
  else
    echo "Using existing access token"
  fi

  echo "Downloading domain database..."
  response=$(curl --silent -w "\n%{http_code}" -L -X GET "$VORI_API_ROOT/pos/domain-data" -H "Content-Type: application/json" -H "X-Vori-Voripos-Provision-Version: $VORIPOS_PROVISION_VERSION" "${curlArgs[@]}")

  # Parse the response
  content=$(sed '$ d' <<< "$response")
  downloadUrl=$( jq -r  '.download_url | select( . != null )' <<< "${content}" )
  expectedHash=$( jq -r  '.checksum.value | select( . != null )' <<< "${content}" )
  expectedAlgorithm=$( jq -r  '.checksum.algorithm | select( . != null )' <<< "${content}" )

  # Create folder and parent directories if does not exist
  mkdir -p "$DOMAIN_FILE_PATH"

  # Download domain database to application support
  fileTimestamp=$(date +%s)
  dbPath="${DOMAIN_FILE_PATH}/${fileTimestamp}-Domain.sqlite3"
  curl --silent -o "$dbPath" "$downloadUrl"

  actualAlgorithm="sha512"
  actualHash=$(sha512sum "$dbPath" | cut -d " " -f 1)

  if [[ "$expectedHash" == "$actualHash" ]]; then
    echo "Hashes match!"
    echo -e "${Green}Successfully downloaded domain database to: $dbPath${Normal}"
  else
    failPath="${DOMAIN_FILE_PATH}/${fileTimestamp}-BAD-HASH-Domain.sqlite3"
    mv "$dbPath" "$failPath"
    echo "${Red}Hashes differ! The downloaded domain database is not valid!${Normal}"
    echo "${Red}Expected: ${expectedAlgorithm}:${expectedHash}${Normal}"
    echo "${Red}Actual:   ${actualAlgorithm}:${actualHash}${Normal}"
    echo "${Red}Database has been moved to: ${failPath}${Normal}"
    exit 1
  fi
fi

echo "Starting background services..."
brew services restart voripos-otel-collector
brew services restart voripos-txn-sync
echo
echo "Sync services started."
echo
echo -e "${Green}VoriPOS provisioning was successful! Restart the app (if it's running) to reload the latest configuration.${Normal}"
