# Container update check

Scripts to check for newer versions of container images - without automatic updates.

Useful, if you want to get notified when there is an update available for a container,
and you want to review possible breaking changes, check for a manual upgrade process or schedule your own downtime.

## Dependencies

Podman or Docker (defaults to podman, if both are available)

Additionally, if run natively (not as container):
- [skopeo](https://github.com/containers/skopeo/blob/main/install.md)
- jq
- sed
- getopt (util-linux)

For notifications via ntfy:
- curl
- hostname (inetutils) `or set NTFY_HOSTNAME`
- whoami (coreutils) `or set NTFY_USER`

## Usage

There are 2 scripts in this repo:
- one to check if a single local image tag differs from a remote tag (`image-check-update.sh`)
  - printing possible newer tags
  - optionally send a notification via ntfy.sh
- another to check for all containers with specific labels, if they can be updated (`containers-check-update.sh`)

### Systemd service

(requires podman)

The systemd service and timer can be installed for the system, all users or a specific user (without enabling or starting):

<details><summary>Install for all users</summary>

```sh
sudo cp container-check-update.service /etc/systemd/user/
sudo cp container-check-update.timer /etc/systemd/user/
```

</details>

<details><summary>Install only for the current user</summary>

```sh
cp container-check-update.service ~/.config/systemd/user/
cp container-check-update.timer ~/.config/systemd/user/
```

</details>

<details><summary>Install for the system</summary>

```sh
sudo cp container-check-update.service /etc/systemd/system/
sudo cp container-check-update.timer /etc/systemd/system/
```

</details>

Then enable and start the podman socket and timer for the current user:

```sh
systemctl --user enable --now podman.socket
systemctl --user enable --now container-check-update.timer
```

Drop the `--user` to enable and start them for the system.

For manual execution run: `systemctl --user start container-check-update`.

### Via Commandline

#### `image-check-update.sh`

```sh
./image-check-update.sh [OPTIONS] IMAGE_REPO IMAGE_TAG [REMOTE_TAG]

# where
# IMAGE_REPO is a container image registry e.g., docker.io/homeassistant/home-assistant
# IMAGE_TAG is a locally existing tag for the image e.g., 2023.4
# REMOTE_TAG is optional and defaults to IMAGE_TAG e.g.. stable

# optional OPTIONS
# --podman or --docker force to use podman or docker, respectively
# -q or --quiet: don't print tag suggestions to stdout (also keep the ntfy message body empty)
# OPTIONS to configure notifications via ntfy.sh (can also be set as environment variables but options take precedence):
# -t or --ntfy-topic [or env $NTFY_TOPIC]: the topic to be notified on the ntfy server
# --ntfy-url [or env $NTFY_URL]: alternative ntfy instance (default is https://ntfy.sh)
# --ntfy-email [or env $NTFY_EMAIL]: additional email to be notified

# optional ENV variables
# SOCKET_URL - (podman only) specify an alternative podman socket
# NTFY_USER - set a username to be part of the notification title, instead of calling `whoami`
# NTFY_HOSTNAME - set a hostname to be part of the notification title, instead of calling `hostname`

# EXIT codes
# 0 if image is up-to-date
# 2 if local image tag hash differs from remote tag
# 1 on script execution error 
```

#### `containers-check-update.sh`

Requires `image-check-update.sh` to be in the current working directory.

```sh
./containers-check-update.sh [OPTIONS]

# optional OPTIONS
# -f or --force : check all containers, not just labelled ones
# --latest : force to check for the `latest` tag

# optional ENV variables
# CONTAINER_UPDATE_LABEL - prefix for the container labels to check (default `updatecheck`)
# CONTAINER_CMD - command or executable to list and inspect containers (default `podman`)
# SOCKET_URL - (podman only) specify an alternative podman socket
# NTFY_URL - default ntfy instance url, in case the corresponding label is not specified on the container
# NTFY_TOPIC - default ntfy topic, in case the corresponding label is not specified on the container
# NTFY_EMAIL - default email to notify, in case the corresponding label is not specified on the container
```

The following container labels are utilized (substitute `updatecheck` with `$CONTAINER_UPDATE_LABEL` if set):
- `updatecheck`: `true` to run the updatecheck, `false` or empty to not run the updatecheck
- `updatecheck.tag`: remote image tag to check against, e.g. `stable` (defaulting to current tag)
- `updatecheck.ntfy.topic`: topic to send the notification to (don't send a notification if not set or empty)
- `updatecheck.ntfy.url`: url of an alternative ntfy instance (default `https://ntfy.sh`)
- `updatecheck.ntfy.email`: also notify this email

### As container (podman only)

In case you don't want to install the additional dependencies, run the scripts as a container:

```sh
podman run --rm \
  --volume $XDG_RUNTIME_DIR/podman:/run/podman:z \ 
  --env NTFY_USER=$USER \
  --env NTFY_HOSTNAME=$HOST \
  -security-opt label=disable \
  IMAGE
```

## Caveats

This was mostly tested and run on openSuse MicroOS using podman.
