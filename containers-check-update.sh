#!/usr/bin/env sh

#set -x

# check all containers for a label and run the update check for all of them.
# additional configuration can be provided via ENV or even as a label.

OPTS=$(getopt --options f --longoptions force,latest -- "$@")
eval set -- "$OPTS"
while true; do
    case "$1" in
        -f|--force) force=true; shift;; # check all containers, not just labeled ones
        --latest) latest=true; shift;; # force to check for latest tag 
        --) shift; break;;
    esac
done

: ${CONTAINER_UPDATE_LABEL:=updatecheck} # io.containers.updatecheck
: ${CONTAINER_CMD:=podman} # e.g. podman or docker

# optional socket url, in case this script is running in a container
if [ -n "$SOCKET_URL" ]; then
    if [ "$CONTAINER_CMD" == "podman" ]; then
        CONTAINER_CMD="podman --url=$SOCKET_URL"
    fi
fi

export CONTAINER_CMD

for container in $($CONTAINER_CMD container ls -a --format '{{ .ID }}'); do
    # check for the labels
    container_info=$($CONTAINER_CMD container inspect $container --format '{{ json }}')
    updatecheck=$(echo $container_info | jq -r ".[0].Config.Labels[${CONTAINER_UPDATE_LABEL}]" 2>/dev/null)

    #echo "[Debug] '$updatecheck' $(test -z $updatecheck && echo empty || echo not empty)"
    if [ -z "$force" ]; then
        if [ -z "$updatecheck"] || [ "$updatecheck" == "0" -o "$updatecheck" == "false" -o "$updatecheck" == "False" -o "$updatecheck" == "no"]; then
            continue
        fi
    fi

    image_tag=$(echo $container_info | jq -r ".[0].ImageName" | sed 's/.*://')
    image_repo=$(echo $container_info | jq -r ".[0].ImageName" | sed 's/:.*//')
    remote_tag=$(echo $container_info | jq -r ".[0].Config.Labels[${CONTAINER_UPDATE_LABEL}.tag]" 2>/dev/null || echo "$image_tag")
    if [ -n "$latest" ]; then
        remote_tag="latest"
    fi
    ntfy_url=$(echo $container_info | jq -r ".[0].Config.Labels[${CONTAINER_UPDATE_LABEL}.ntfy.url]" 2>/dev/null)
    ntfy_topic=$(echo $container_info | jq -r ".[0].Config.Labels[${CONTAINER_UPDATE_LABEL}.ntfy.topic]" 2>/dev/null)
    ntfy_email=$(echo $container_info | jq -r ".[0].Config.Labels[${CONTAINER_UPDATE_LABEL}.ntfy.email]" 2>/dev/null)

    # updatecheck label is set, assuming we want to check for an update
    ./image-check-update.sh "$image_repo" "$image_tag" "$remote_tag"
done