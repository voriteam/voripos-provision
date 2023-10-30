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

## Distribution
Create a release on GitHub, and follow the instructions at https://github.com/voriteam/homebrew-voripos to update the 
tap with the latest version.
