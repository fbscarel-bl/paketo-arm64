#!/bin/bash
set -eo pipefail

docker build . -t dashaun/jammy-build \
--build-arg sources="deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy main restricted universe multiverse \n deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted universe multiverse \n deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse" \
--build-arg packages="build-essential ca-certificates curl git jq libgmp-dev libssl3 libyaml-0-2 netbase openssl tzdata xz-utils zlib1g-dev"