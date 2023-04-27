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
    updatecheck=$(echo $container_info | jq -r ".[0].Config.Labels[\"${CONTAINER_UPDATE_LABEL}\"]" 2>/dev/null)
    container_name=$(echo $container_info | jq -r ".[0].Name" 2>/dev/null)

    #echo "[Debug] '$updatecheck' $(test -z $updatecheck && echo empty || echo not empty)"
    if [ -z "$force" ]; then
        case "$updatecheck" in
            0|false|False|null|NULL|no|No|NO) echo "[$container_name] not configured to update: updatecheck = '$updatecheck'"; continue;;
            *) echo "[$container_name] updatecheck set to '$updatecheck'";;
        esac
    else
        echo "[Debug] force is set"
    fi

    image_tag=$(echo $container_info | jq -r ".[0].ImageName" | sed 's/.*://')
    image_repo=$(echo $container_info | jq -r ".[0].ImageName" | sed 's/:.*//')
    remote_tag=$(echo $container_info | jq -r ".[0].Config.Labels[\"${CONTAINER_UPDATE_LABEL}.tag\"]" 2>/dev/null | sed 's/^null$//' || echo "$image_tag")
    if [ -n "$latest" ]; then
        remote_tag="latest"
    fi
    : ${remote_tag:=$image_tag} # set default if empty    
    ntfy_url=$(echo $container_info | jq -r ".[0].Config.Labels[\"${CONTAINER_UPDATE_LABEL}.ntfy.url\"]" 2>/dev/null | sed 's/^null$//')
    ntfy_topic=$(echo $container_info | jq -r ".[0].Config.Labels[\"${CONTAINER_UPDATE_LABEL}.ntfy.topic\"]" 2>/dev/null | sed 's/^null$//')
    ntfy_email=$(echo $container_info | jq -r ".[0].Config.Labels[\"${CONTAINER_UPDATE_LABEL}.ntfy.email\"]" 2>/dev/null | sed 's/^null$//')

    echo "[$container_name] Checking $image_repo:$image_tag against tag $remote_tag"

    # updatecheck label is set, assuming we want to check for an update
    echo -n "[$container_name] "
    ./image-check-update.sh --ntfy-url="${ntfy_url:=$NTFY_URL}" --ntfy-topic="${ntfy_topic:=$NTFY_TOPIC}" --ntfy-email="${ntfy_email:=$NTFY_EMAIL}" "$image_repo" "$image_tag" "$remote_tag"
    
    #test -z "$ntfy_topic" && echo "[$container_name] Ntfy not configured" || echo "[$container_name] Notified via $ntfy_url/$ntfy_topic and $ntfy_email"
done

exit 0