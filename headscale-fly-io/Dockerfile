FROM alpine AS fetcher
RUN apk add wget tar
RUN arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/ > /tmp/arch

FROM fetcher AS litestream
RUN arch=$(cat /tmp/arch) &&\
    wget https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-${arch}.tar.gz && \
    tar -xf litestream-v0.3.13-linux-${arch}.tar.gz

FROM alpine
RUN apk add age envsubst nginx nodejs npm
COPY --from=ghcr.io/juanfont/headscale:v0.28.0 ko-app/headscale /usr/bin/headscale
COPY --from=litestream /litestream /usr/bin/litestream
COPY --from=minio/mc:RELEASE.2024-10-02T08-27-28Z /usr/bin/mc /usr/bin/mc
COPY --from=ghcr.io/tale/headplane:0.6.2 /app/build /opt/headplane/build
COPY --from=ghcr.io/tale/headplane:0.6.2 /app/drizzle /opt/headplane/drizzle
COPY --from=ghcr.io/tale/headplane:0.6.2 /app/node_modules /opt/headplane/node_modules
COPY --from=ghcr.io/tale/headplane:0.6.2 /var/lib/headplane /var/lib/headplane
WORKDIR /etc/headscale
VOLUME /var/lib/headscale
COPY entrypoint.sh litestream-entrypoint.sh config.template.yaml config-oidc.template.yaml config-headplane.template.yaml nginx.template.conf ./
RUN addgroup -S headscale && adduser -S headscale -G headscale
RUN mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale /var/lib/headplane /run/nginx && \
    touch /etc/litestream.yml && \
    chown -R headscale:headscale /etc/headscale /var/lib/headscale /var/run/headscale /var/lib/headplane /etc/litestream.yml /run/nginx /opt/headplane
USER headscale
ENTRYPOINT [ "/bin/sh", "/etc/headscale/entrypoint.sh" ]
