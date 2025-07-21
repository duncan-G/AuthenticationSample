#!/bin/bash
echo "WARNING: This script is not complete. It is a work in progress."

echo "Installing brew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "Installing dotnet"
brew install dotnet

echo "Installing trusted certificates"
brew install mkcert
brew install nss # Installs cert for firefox
mkcert -install

echo "Installing AWS CLI"
brew install awscli

echo "Installing bash"
brew install bash

echo "Installing jq"
brew install jq

echo "Installing github cli"
brew install gh

echo "WARNING: This script is not complete. It is a work in progress."