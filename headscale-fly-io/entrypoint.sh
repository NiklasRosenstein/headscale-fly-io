#!/bin/sh

set -eu

info() {
    echo "[ entrypoint - INFO ]" "$@"
}

error() {
    echo "[ entrypoint - ERROR ]" "$@"
}

info_run() {
    info "$@"
    "$@"
}

assert_is_set() {
    eval "val=\${$1+x}"
    if [ -z "$val" ]; then
        error "missing expected environment variable \"$1\""
        exit 1
    fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        error "missing expected file \"$1\""
        exit 1
    fi
}

HEADSCALE_CONFIG_PATH=/etc/headscale/config.yaml
HEADSCALE_DB_PATH=/var/lib/headscale/db.sqlite
NOISE_PRIVATE_KEY_FILE=/var/lib/headscale/noise_private.key

# This file must be configured through a secret and mounted via the fly.toml configuration.
# assert_file_exists $NOISE_PRIVATE_KEY_FILE
assert_is_set NOISE_PRIVATE_KEY
info "writing $NOISE_PRIVATE_KEY_FILE"
echo "$NOISE_PRIVATE_KEY" > /$NOISE_PRIVATE_KEY_FILE

# These should be available automatically simply by enabling the Fly.io Tigris object storage extension.
assert_is_set AWS_ACCESS_KEY_ID
assert_is_set AWS_SECRET_ACCESS_KEY
assert_is_set AWS_REGION
assert_is_set AWS_ENDPOINT_URL_S3
assert_is_set BUCKET_NAME

export LITESTREAM_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export LITESTREAM_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

info "generating /etc/litestream.yml"
cat <<EOF >/etc/litestream.yml
dbs:
  - path: /var/lib/headscale/db.sqlite
    replicas:
      # See https://litestream.io/reference/config/#s3-replica
      - type: s3
        bucket: $BUCKET_NAME
        path: headscale.db
        region: $AWS_REGION
        endpoint: $AWS_ENDPOINT_URL_S3
EOF

# Generate the Headscale configuration file by substituting environment variables.
info "generating $HEADSCALE_CONFIG_PATH"
# shellcheck disable=SC3060
cat ${HEADSCALE_CONFIG_PATH/.yaml/.template.yaml/} | envsubst > $HEADSCALE_CONFIG_PATH
info "generated $HEADSCALE_CONFIG_PATH:"
cat $HEADSCALE_CONFIG_PATH

info_run litestream restore -if-db-not-exists -if-replica-exists -replica s3 "$HEADSCALE_DB_PATH"
info_run litestream replicate -exec "headscale serve"
