#!/bin/bash
set -eo pipefail

docker build . -t dashaun/jammy-run \
--build-arg packages="base-files ca-certificates libc6 libssl3 netbase openssl tzdata zlib1g"