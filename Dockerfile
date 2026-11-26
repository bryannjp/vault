# Image for the one-off "deploy" job in docker-compose.yml.
# Same Foundry version as local development (forge --version), so builds behave the same.
FROM ghcr.io/foundry-rs/foundry:v1.7.0

# Root inside this short-lived job container, so forge can write its build output to /app.
USER root
WORKDIR /app

# The exact compiler the contracts need (pragma solidity 0.8.36), from the official release.
# Docker checks the SHA-256, so a tampered or corrupted download fails the build.
# FOUNDRY_SOLC makes forge use this file instead of looking up and downloading a compiler itself.
ADD --chmod=755 --checksum=sha256:c8d35afdddc3cd2743ee88b8f25e0fecd16e2bdd5f2120f37e52cd9cc45ae0e6 \
    https://github.com/ethereum/solidity/releases/download/v0.8.36/solc-static-linux /usr/local/bin/solc
ENV FOUNDRY_SOLC=/usr/local/bin/solc

# Only what's needed to compile and deploy (see .dockerignore).
COPY foundry.toml foundry.lock ./
COPY lib lib
COPY src src
COPY test/mocks test/mocks
COPY script script

# Compile while building the image, not every time the container starts.
RUN forge build src script

ENTRYPOINT ["/bin/sh", "script/docker-deploy.sh"]
