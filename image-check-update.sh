#!/usr/bin/env sh

###########################################################################
# PROGRAM:
#    Check if a local image tag differs from a remote tag, printing
#    possible newer tags and optionally sending a notification.
###########################################################################
#    Copyright (C) 2023 stendler
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
###########################################################################

#set -x

# podman or docker if not explicitly specified
if command -v podman 1>/dev/null; then
    CONTAINER_CMD="${CONTAINER_CMD:=podman}"
elif command -v docker 1>/dev/null; then
    CONTAINER_CMD="${CONTAINER_CMD:=docker}"
fi

OPTS=$(getopt --options qt: --longoptions quiet,docker,podman,ntfy-topic:,ntfy-email:,ntfy-url: -- "$@")
eval set -- "$OPTS"
while true; do
    case "$1" in
        -t|--ntfy-topic) NTFY_TOPIC="$2"; shift 2;;
        --ntfy-email) NTFY_EMAIL="$2"; shift 2;;
        --ntfy-url) NTFY_URL="$2"; shift 2;;
        --podman) command -v podman 1>/dev/null && CONTAINER_CMD="podman" || exit 1; shift;;
        --docker) command -v docker 1>/dev/null && CONTAINER_CMD="docker" || exit 1; shift;;
        -q|--quiet) quiet=true; shift;; # still printing to stderr, but not to stdout
        --) shift; break;;
        *) echo "Unkown argument: $1"; exit 1;;
    esac
done

if [ -z "${CONTAINER_CMD}" ]; then
    echo 1>&2 "Neither podman nor docker present and no CONTAINER_CMD set."
    exit 1
fi

# optional socket url, in case this script is running in a container
if [ -n "$SOCKET_URL" ]; then
    if [ "$CONTAINER_CMD" = "podman" ]; then
        CONTAINER_CMD="podman --url=$SOCKET_URL"
    fi
fi

if [ -z "$1" ]; then
    echo >&2 "Image repository url (including e.g. \"docker.io/\") must be specified."
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

local_digest=$($CONTAINER_CMD image inspect "$repo:$image_tag" | jq -r '.[0].Digest')
if [ -z "$local_digest" ]; then
    echo >&2 "No local image exists with this tag. Check $CONTAINER_CMD image ls"
    exit 1
fi
remote_inspect=$(skopeo inspect "docker://$repo:$remote_tag")
remote_layers=$(echo "$remote_inspect" | jq -r '.Layers')
if [ -z "$remote_layers" ]; then
    exit 1 # no error message needed, was probably already printed to stderr
fi

# this may throw an error if the manifest does not exist on the remote anymore - but that means, an update is probably available
local_inspect=$(skopeo inspect "docker://$repo@$local_digest")
local_layers=$(echo "$local_inspect" | jq -r '.Layers')

if [ "$remote_layers" = "$local_layers" ]; then
    if [ "$remote_tag" = "$image_tag" ]; then
        echo >&2 "$1:$image_tag is up-to-date"
    else
        echo >&2 "$1:$image_tag is up-to-date with tag $remote_tag"
    fi
    exit 0
fi

# declare locally used variables
message=""
ntfy_mail_header=""

if [ "$remote_tag" = "$image_tag" ]; then
    echo >&2 "$1:$image_tag can be updated."
else
    echo >&2 "$1:$image_tag is not up-to-date with tag $remote_tag."
    if [ -z "$quiet" ]; then
        echo >&2 "These tags could be newer:"
        # get the list of tags starting from the image_tag
        tag_list=$(echo "$remote_inspect" | jq ".RepoTags as \$tags | \$tags | index(\"${image_tag}\") as \$start | \$tags[\$start+1:]")
        echo "$tag_list"
        message=$(echo "Possible update candidates: $tag_list" | head -c 4096)
    fi
fi

if [ -n "$NTFY_TOPIC" ]; then
    if [ -n "$NTFY_EMAIL" ]; then
        NTFY_EMAIL="Email: $NTFY_EMAIL"
        ntfy_mail_header="-H"
    fi

    curl >/dev/null 2>&1 -H "Tags: whale" -H "Firebase: no" "$ntfy_mail_header" "$NTFY_EMAIL" \
    -H "Title: ${NTFY_USER:=$(whoami)}@${NTFY_HOSTNAME:=$(hostname)}: $repo:$image_tag is outdated compared to remote tag '$remote_tag'" \
    -d "$message" "${NTFY_URL:=https://ntfy.sh}/$NTFY_TOPIC"
fi

exit 2