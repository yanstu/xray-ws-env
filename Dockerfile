FROM alpine:3.20
ARG XRAY_VERSION=v26.10.31
RUN apk add --no-cache ca-certificates wget unzip \
 && wget -qO /tmp/x.zip https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip \
 && wget -qO /tmp/x.dgst https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip.dgst \
 && test "$(sha256sum /tmp/x.zip | cut -d' ' -f1)" = "$(grep -i 'SHA2-256' /tmp/x.dgst | head -1 | awk '{print $NF}')" \
 && unzip -o /tmp/x.zip xray -d /usr/local/bin && chmod +x /usr/local/bin/xray && rm -f /tmp/x.*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
