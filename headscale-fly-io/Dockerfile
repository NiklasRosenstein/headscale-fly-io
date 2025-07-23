FROM alpine AS fetcher
RUN apk add wget tar
RUN arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/ > /tmp/arch

FROM fetcher AS litestream
RUN arch=$(cat /tmp/arch) &&\
    wget https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-${arch}.tar.gz && \
    tar -xf litestream-v0.3.13-linux-${arch}.tar.gz

FROM alpine
RUN apk add age envsubst
COPY --from=ghcr.io/juanfont/headscale:v0.26.1 ko-app/headscale /usr/bin/headscale
COPY --from=litestream /litestream /usr/bin/litestream
COPY --from=minio/mc:RELEASE.2024-10-02T08-27-28Z /usr/bin/mc /usr/bin/mc
WORKDIR /etc/headscale
VOLUME /var/lib/headscale
COPY entrypoint.sh litestream-entrypoint.sh config.template.yaml config-oidc.template.yaml .
RUN addgroup -S headscale && adduser -S headscale -G headscale
RUN mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale && \
    touch /etc/litestream.yml && \
    chown -R headscale:headscale /etc/headscale /var/lib/headscale /var/run/headscale /etc/litestream.yml
USER headscale
ENTRYPOINT [ "/bin/sh", "/etc/headscale/entrypoint.sh" ]
