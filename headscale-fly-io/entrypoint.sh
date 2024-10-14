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

# The HEADSCALE_SERVER_URL variable was removed.
if [ -n "${HEADSCALE_SERVER_URL:-}" ]; then
    error "HEADSCALE_SERVER_URL is no longer supported, set HEADSCALE_DOMAIN_NAME instead"
    exit 1
fi

# Set default values for configuration variables for use with envsubst.
export HEADSCALE_DOMAIN_NAME="${HEADSCALE_DOMAIN_NAME:-${FLY_APP_NAME}.fly.dev}"
export HEADSCALE_DNS_BASE_DOMAIN="${HEADSCALE_DNS_BASE_DOMAIN:-tailnet}"
export HEADSCALE_LOG_LEVEL="${HEADSCALE_LOG_LEVEL:-info}"
export HEADSCALE_PREFIXES_V4="${HEADSCALE_PREFIXES_V4:-100.64.0.0/10}"
export HEADSCALE_PREFIXES_V6="${HEADSCALE_PREFIXES_V6:-fd7a:115c:a1e0::/48}"
export HEADSCALE_PREFIXES_ALLOCATION="${HEADSCALE_PREFIXES_ALLOCATION:-random}"
export HEADSCALE_EPHEMERAL_NODE_INACTIVITY_TIMEOUT="${HEADSCALE_EPHEMERAL_NODE_INACTIVITY_TIMEOUT:-30m}"

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
    export HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN="${HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN:-false}"
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

maybe_idle

export LITESTREAM_DATABASE_PATH=/var/lib/headscale/db.sqlite
exec /etc/headscale/litestream-entrypoint.sh "headscale serve"