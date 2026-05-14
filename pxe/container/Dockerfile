FROM alpine:3.20

RUN apk add --no-cache ca-certificates dnsmasq nginx wget && \
    mkdir -p /run/nginx /srv/pxe/http /srv/pxe/tftp && \
    wget -O /srv/pxe/tftp/undionly.kpxe https://boot.ipxe.org/x86_64-pcbios/undionly.kpxe && \
    wget -O /srv/pxe/tftp/ipxe.efi https://boot.ipxe.org/x86_64-efi/ipxe.efi && \
    test -f /srv/pxe/tftp/undionly.kpxe; \
    test -f /srv/pxe/tftp/ipxe.efi

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 67/udp 69/udp 4011/udp 8080/tcp

ENTRYPOINT ["/entrypoint.sh"]
