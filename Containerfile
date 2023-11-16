FROM quay.io/podman/stable

LABEL RUN podman run --rm --volume \$XDG_RUNTIME_DIR/podman:/run/podman:z --env NTFY_USER=\$USER --env NTFY_HOSTNAME=\$HOST -security-opt label=disable IMAGE

ENTRYPOINT [ "/containers-check-update.sh" ]

ENV SOCKET_URL=unix:///run/podman/podman.sock
ENV NTFY_URL=https://ntfy.sh
#set NTFY_TOPIC if you want to utilise ntfy
#set NTFY_EMAIL if you want to additionally get notified on this email

RUN echo "max_parallel_downloads=20" >> /etc/dnf/dnf.conf && \
    sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/fedora-cisco-openh264.repo && \
    sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/fedora-updates-testing.repo && \
    dnf upgrade --refresh -y && \
    dnf install -y jq podman skopeo curl --exclude container-selinux && \
    dnf clean all && \
    rm -rf /var/cache /var/log/dnf* /var/log/yum.*
COPY image-check-update.sh /
COPY containers-check-update.sh /
