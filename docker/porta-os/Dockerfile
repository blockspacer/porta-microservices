FROM registry.access.redhat.com/rhel-atomic

ARG PORTA_GIT_COMMIT=unspecified
ARG PORTA_GIT_TAG=unspecified
ARG PORTA_GIT_BRANCH=master

ENV PORTA_GIT_TAG=$PORTA_GIT_TAG
ENV PORTA_GIT_COMMIT=$PORTA_GIT_COMMIT

LABEL PORTA_GIT_TAG=$PORTA_GIT_TAG
LABEL PORTA_GIT_COMMIT=$PORTA_GIT_COMMIT
LABEL PORTA_GIT_BRANCH=$PORTA_GIT_BRANCH

LABEL summary="Base image with essential libraries and tools used as a base for builder images like perl, python, ruby, etc."
LABEL maintainer="PortaOne Inc."
