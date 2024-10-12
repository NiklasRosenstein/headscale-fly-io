FROM alpine AS fetcher
RUN apk add wget tar
RUN arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/ > /tmp/arch

FROM fetcher AS litestream
RUN arch=$(cat /tmp/arch) &&\
    wget https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-${arch}.tar.gz && \
    tar -xf litestream-v0.3.13-linux-${arch}.tar.gz

FROM fetcher AS geesefs
RUN arch=$(cat /tmp/arch) &&\
    wget https://github.com/yandex-cloud/geesefs/releases/download/v0.41.3/geesefs-linux-${arch} -O geesefs && \
    chmod +x geesefs

FROM alpine
RUN apk add age envsubst
COPY --from=ghcr.io/juanfont/headscale:v0.23.0 ko-app/headscale /usr/bin/headscale
COPY --from=litestream /litestream /usr/bin/litestream
COPY --from=geesefs /geesefs /usr/bin/geesefs
COPY --from=minio/mc:RELEASE.2024-10-02T08-27-28Z /usr/bin/mc /usr/bin/mc
WORKDIR /etc/headscale
VOLUME /var/lib/headscale
COPY entrypoint.sh config.template.yaml config-oidc.template.yaml .

# NOTE: Because GeeseFS --uid seems to be broken (even root gets permission denied errors when usign it, but maybe
#       that is just on Fly.io?), we can't run Headscale as non-root at the moment.
# RUN echo 'headscale ALL=(ALL) NOPASSWD:SETENV: /usr/bin/geesefs' >> /etc/sudoers
# RUN addgroup -S headscale && adduser -S headscale -G headscale
# RUN mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale && \
#     touch /etc/litestream.yml && \
#     chown -R headscale:headscale /etc/headscale /var/lib/headscale /var/run/headscale /etc/litestream.yml
# USER headscale
RUN mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale

ENTRYPOINT [ "/bin/sh", "/etc/headscale/entrypoint.sh" ]
