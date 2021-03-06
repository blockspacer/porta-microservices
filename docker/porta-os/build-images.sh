#!/bin/sh
set -e

APP_NAME="porta-os"

IMAGE_NAME=maxkondr/$APP_NAME

# build main image
docker build --pull -t $IMAGE_NAME --build-arg PORTA_GIT_COMMIT=$(git rev-parse HEAD) --build-arg PORTA_GIT_BRANCH=$(git branch --contains HEAD | egrep -v "detached" | sed -e 's/^* //' | xargs)  --build-arg PORTA_GIT_TAG=$(git describe --abbrev HEAD 2>/dev/null) .
docker push $IMAGE_NAME
