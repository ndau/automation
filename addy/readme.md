# addy

This is a helper program that converts base64 private keys from Tendermint's node_key.json file and turns them into valid node addresses. The process goes base_64_priv_key → priv_key → pub_key → SHA256-20 hash in hex.

This uses the minimal amount of code from Tendermint's repo, which is just to turn the private key into a public key. The last step is to sha256 and truncate to 20 bytes.

`./build.sh` builds the binaries for Linux, OSX and Windows. They are checked in to this repo because they need to be available for running in CircleCI. If you update this code, please rebuild and commit the binaries.
