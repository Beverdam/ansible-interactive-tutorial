# Named IMAGE_NAMESPACE, not USER: GNU Make re-exports variables that were
# already present in the inherited environment to child process
# environments even after a Makefile reassigns them, and `USER` is such a
# variable (the shell sets it to the real login name). A Makefile `USER=`
# here was shadowing the real $USER for every command make runs -- rootless
# podman's subuid/subgid lookup reads $USER to find the current user's
# subordinate ID range, so it was looking up "beverdam" (a name with no
# /etc/subuid entry) instead of the actual runner account, breaking `podman
# build` in the t6-podman CI job. Root-run builds (e.g. local root shells)
# never hit this: root doesn't need rootless UID remapping at all.
IMAGE_NAMESPACE=beverdam
TAG=2.0

# `?=` (not `=`): honors an already-set CONTAINER_ENGINE (e.g. passed in by
# tutorial.sh's auto-build step, or exported by a podman user calling this
# Makefile directly) while still defaulting sanely for a bare `make`.
# Matches tutorial.sh's own CONTAINER_ENGINE pattern -- without this, the
# `docker` calls below were hardcoded regardless of what a user configured
# tutorial.sh to use, so `CONTAINER_ENGINE=podman ./tutorial.sh` on a
# machine with no `docker` binary at all would fail here with "docker:
# command not found" even though tutorial.sh's own commands honored podman
# correctly.
CONTAINER_ENGINE ?= docker

# build_all (not `all`) is the default: it only builds, it never pushes.
# The original default goal was `all` (build_all + push_all), so a bare
# `make` attempted to push to turkenh's Docker Hub account -- which a fork
# doesn't have write access to, and even on your own account a push should
# be a deliberate `make push_all`, not what a plain build invocation does.
.DEFAULT_GOAL := build_all

build:
	$(CONTAINER_ENGINE) build -t $(IMAGE_NAMESPACE)/${IMAGE}:${TAG} -f ${IMAGE}/Dockerfile .

push:
	$(CONTAINER_ENGINE) push $(IMAGE_NAMESPACE)/${IMAGE}:${TAG}

build_and_push: build push

build_all:
	IMAGE=ansible-managed-host $(MAKE) build
	IMAGE=ansible-tutorial $(MAKE) build

push_all:
	IMAGE=ansible-managed-host $(MAKE) push
	IMAGE=ansible-tutorial $(MAKE) push

all: build_all push_all
