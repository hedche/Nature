#!/bin/sh

set -eu

PXE_SERVER_IP="${PXE_SERVER_IP:-10.30.1.20}"
HTTP_PORT="${HTTP_PORT:-8080}"
PXE_DHCP_RANGE="${PXE_DHCP_RANGE:-10.30.1.0,proxy,255.255.255.0}"

if [ ! -d /srv/pxe/http ]; then
    echo "Missing HTTP asset directory: /srv/pxe/http" >&2
    exit 1
fi

sed "s|\${HTTP_PORT}|${HTTP_PORT}|g" \
    /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

cat > /etc/dnsmasq.conf <<EOF
port=0
log-dhcp
enable-tftp
tftp-root=/srv/pxe/tftp
dhcp-range=${PXE_DHCP_RANGE}
dhcp-userclass=set:ipxe,iPXE
dhcp-match=set:bios,option:client-arch,0
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:ipxe,http://${PXE_SERVER_IP}:${HTTP_PORT}/boot.ipxe
dhcp-boot=tag:efi64,ipxe.efi
dhcp-boot=tag:bios,undionly.kpxe
dhcp-boot=undionly.kpxe
pxe-service=x86PC,"Nature PXE BIOS",undionly.kpxe
pxe-service=BC_EFI,"Nature PXE UEFI",ipxe.efi
pxe-service=X86-64_EFI,"Nature PXE UEFI",ipxe.efi
EOF

nginx
exec dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf

