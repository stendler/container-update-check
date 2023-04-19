#!/usr/bin/env sh

# podman or docker
CONTAINER_CMD="${CONTAINER_CMD:=podman}"

if [ "$1" == "--docker" ]; then
    CONTAINER_CMD="docker"
    shift
elif [ "$1" == "--podman" ]; then
    CONTAINER_CMD="podman"
    shift
fi

# optional socket url, in case this script is running in a container
if [ -n "$SOCKET_URL" ]; then
    if [ "$CONTAINER_CMD" == "podman" ]; then
        CONTAINER_CMD="podman --url=$SOCKET_URL"
    fi
fi

if [ -z "$1" ]; then
    echo >&2 "Image repository url (including e.g. "docker.io/") must be specified."
    exit 1
fi
repo="$1"

image_tag='latest'
if [ -n "$2" ]; then
    image_tag="$2"
fi

remote_tag="$image_tag"
if [ -n "$3" ]; then
    remote_tag="$3"
fi

local_digests=$($CONTAINER_CMD image inspect "$repo:$image_tag" | jq -r '.[0].RepoDigests | join(" ")' | sed -e 's/[a-z0-9\./_-]*@//g')
if [ -z "$local_digests" ]; then
    echo >&2 "No local image exists with this tag. Check $CONAINER_CMD image ls"
    exit 1
fi
remote_digest=$(skopeo inspect "docker://$repo:$remote_tag" | jq -r '.Digest')
if [ -z "$remote_digest" ]; then
    exit 1 # no error message needed, was probably already printed to stderr
fi

for digest in $local_digests; do
    if [ "$remote_digest" == "$digest" ]; then
        if [ "$remote_tag" == "$image_tag" ]; then
            echo >&2 "$1:$image_tag is up-to-date"
        else
            echo >&2 "$1:$image_tag is up-to-date with tag $remote_tag"
        fi
        exit 0
    fi
done

if [ "$remote_tag" == "$image_tag" ]; then
    echo >&2 "$1:$image_tag can be updated."
else
    echo >&2 "$1:$image_tag is not up-to-date with tag $remote_tag. These tags could be newer:"
    tag_list=$(skopeo list-tags "docker://$repo" | jq ".Tags as \$tags | \$tags | index(\"${image_tag}\") as \$start | \$tags[\$start+1:]")
    if [ -n "$NTFY_TOPIC" ]; then
        if [ -n "$NTFY_EMAIL" ]; then
            NTFY_EMAIL="Email: $NTFY_EMAIL"
            ntfy_mail_header="-H"
        fi
        curl >/dev/null 2>&1 -H "Tags: whale" -H "Firebase: no" "$ntfy_mail_header" "$NTFY_EMAIL" \
            -H "Title: $(whoami)@$(hostname): $repo:$image_tag is outdated compared to $remote_tag" \
            -d "Possible update candidates: $tag_list" "${NTFY_URL:=https://ntfy.sh/}$NTFY_TOPIC"
    fi
    echo "$tag_list"
fi
exit 2