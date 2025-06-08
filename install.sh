#!/bin/bash

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
