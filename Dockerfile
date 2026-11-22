FROM alpine:3.20
ARG XRAY_VERSION=v26.10.31
COPY download-xray.sh /tmp/download-xray.sh
RUN apk add --no-cache ca-certificates wget unzip \
 && XRAY_VERSION="${XRAY_VERSION}" sh /tmp/download-xray.sh \
 && rm -f /tmp/download-xray.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
