#!/bin/sh

set -eu

debug() {
    >&2 echo "[ entrypoint - DEBUG ]" "$@"
}

info() {
    >&2 echo "[ entrypoint - INFO ]" "$@"
}

error() {
    >&2 echo "[ entrypoint - ERROR ]" "$@"
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

maybe_idle() {
    if [ "${ENTRYPOINT_IDLE:-false}" = "true" ]; then
        info "ENTRYPOINT_IDLE=true, entering idle state"
        sleep infinity
    fi
}

on_error() {
    [ $? -eq 0 ] && exit
    error "an unexpected error occurred."
    maybe_idle
}

trap 'on_error' EXIT

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
assert_is_set AGE_SECRET_KEY

export LITESTREAM_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export LITESTREAM_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
AGE_PUBLIC_KEY="$(echo "$AGE_SECRET_KEY" | age-keygen -y)"

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
    # See https://litestream.io/reference/config/#encryption
    age:
      identities:
      - "$AGE_SECRET_KEY"
      recipients:
      - "$AGE_PUBLIC_KEY"
    # See https://litestream.io/reference/config/#retention-period
    retention: "${LITESTREAM_RETENTION:-24h}"
    retention-check-interval: "${LITESTREAM_RETENTION_CHECK_INTERVAL:-1h}"
    # https://litestream.io/reference/config/#validation-interval
    validation-interval: "${LITESTREAM_VALIDATION_INTERVAL:-12h}"
EOF

info "configuring mc"
mc alias set s3 "$AWS_ENDPOINT_URL_S3" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

if [ "${ENTRYPOINT_DEBUG:-}" = "true" ]; then
    debug "ENTRYPOINT_DEBUG is set: set -x"
    set -x
fi

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
    assert_is_set HEADSCALE_OIDC_CLIENT_ID
    assert_is_set HEADSCALE_OIDC_CLIENT_SECRET
    export HEADSCALE_OIDC_SCOPES="${HEADSCALE_OIDC_SCOPES:-openid, profile, email}"
    export HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN="${HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN:-true}"
    export HEADSCALE_OIDC_EXPIRY="${HEADSCALE_OIDC_EXPIRY:-180d}"
    export HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN="${HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN:-true}"
    export HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE="${HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE:-true}"
    info "generating OIDC appendix for $HEADSCALE_CONFIG_PATH"
    # shellcheck disable=SC3060
    envsubst < "${HEADSCALE_CONFIG_PATH/.yaml/-oidc.template.yaml}" >> $HEADSCALE_CONFIG_PATH
fi

if [ "${ENTRYPOINT_DEBUG:-}" = "true" ]; then
    debug "contents of $HEADSCALE_CONFIG_PATH:"
    cat "$HEADSCALE_CONFIG_PATH"
    debug "end contents of $HEADSCALE_CONFIG_PATH"
fi

# Check if there is an existing database to import from S3.
if [ "${IMPORT_DATABASE:-}" = "true" ] && mc find "s3/$BUCKET_NAME/import-db.sqlite" 2> /dev/null > /dev/null; then
    info "found \"import-db.sqlite\" in bucket, importing that database instead of restoring with litestream"
    mc cp "s3/$BUCKET_NAME/import-db.sqlite" "$HEADSCALE_DB_PATH"
elif [ "${LITESTREAM_ENABLED:-true}" = "true" ]; then
    info_run litestream restore -if-db-not-exists -if-replica-exists -replica s3 "$HEADSCALE_DB_PATH"
fi

maybe_idle

# Run Headscale.
if [ "${LITESTREAM_ENABLED:-true}" = "true" ]; then
    info_run exec litestream replicate -exec "headscale serve"
else
    info_run exec headscale serve
fi
