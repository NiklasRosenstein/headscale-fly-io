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


# Set default values for configuration variables for use with envsubst.
export HEADSCALE_SERVER_URL="${HEADSCALE_SERVER_URL:-https://${FLY_APP_NAME}.fly.dev}"
export HEADSCALE_DNS_BASE_DOMAIN="${HEADSCALE_DNS_BASE_DOMAIN:-tailnet}"
export HEADSCALE_LOG_LEVEL="${HEADSCALE_LOG_LEVEL:-info}"
export HEADSCALE_PREFIXES_V4="${HEADSCALE_PREFIXES_V4:-100.64.0.0/10}"
export HEADSCALE_PREFIXES_V6="${HEADSCALE_PREFIXES_V6:-fd7a:115c:a1e0::/48}"
export HEADSCALE_PREFIXES_ALLOCATION="${HEADSCALE_PREFIXES_ALLOCATION:-random}"

# Generate the Headscale configuration file by substituting environment variables.
info "generating $HEADSCALE_CONFIG_PATH"
# shellcheck disable=SC3060
envsubst < "${HEADSCALE_CONFIG_PATH/.yaml/.template.yaml}" > $HEADSCALE_CONFIG_PATH

# Append OIDC configuration if enabled.
if [ -n "${HEADSCALE_OIDC_ISSUER:-}" ]; then
    export HEADSCALE_OIDC_SCOPES="${HEADSCALE_OIDC_SCOPES:-openid, profile, email}"
    export HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN="${HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN:-true}"
    export HEADSCALE_OIDC_EXPIRY="${HEADSCALE_OIDC_EXPIRY:-180d}"
    export HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN="${HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN:-true}"
    export HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE="${HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE:-true}"
    # shellcheck disable=SC3060
    envsubst < "${HEADSCALE_CONFIG_PATH/.yaml/-oidc.template.yaml}" >> $HEADSCALE_CONFIG_PATH
fi

info_run litestream restore -if-db-not-exists -if-replica-exists -replica s3 "$HEADSCALE_DB_PATH"
info_run litestream replicate -exec "headscale serve"
