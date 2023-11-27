# VoriPOS Provisioning Tool

## Installation
This service is distributed via Homebrew.

```shell
brew tap voriteam/voripos
brew install voripos-provision
```

After installing, run the command below to provision the system:

```shell
voripos-provision.sh
```

You can run against a non-production API server by setting the `VORI_API_ROOT` environment variable:

```shell
VORI_API_ROOT=https://api.dev.vori.com/v1 voripos-provision.sh
```

## Re-provision
Re-provision systems by running the command below. This will use OIDC to authenticate to the API and download lane data.

```shell
voripos-provision.sh -r
```

## Unattended mode
Provisioning can be run without user input by passing the `-s` (silent) flag. This requires the token to be 
passed using the `-t` flag. _Remember to wrap the token in quotes._

```shell
voripos-provision.sh -s -t "ABC-1234"
```

No token is required when re-provisioning an already-provisioned system.

```shell
voripos-provision.sh -rs
```

## Distribution
1. Update `VORIPOS_PROVISION_VERSION`.
2. Create a release on GitHub.
3. Follow the instructions at https://github.com/voriteam/homebrew-voripos to update the tap with the latest version.
