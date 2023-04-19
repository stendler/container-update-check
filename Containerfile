FROM quay.io/podman/stable

ENTRYPOINT [ "/containers-check-update.sh" ]

ENV SOCKET_URL=unix:///run/podman/podman.sock
ENV NTFY_URL=https://ntfy.sh/
#set NTFY_TOPIC if you want to utilise ntfy
#set NTFY_EMAIL if you want to additionally get notified on this email

RUN dnf update
RUN dnf install -y jq podman skopeo curl
COPY image-check-update.sh /
COPY containers-check-update.sh /