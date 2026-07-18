USER=beverdam
TAG=2.0

# build_all (not `all`) is the default: it only builds, it never pushes.
# The original default goal was `all` (build_all + push_all), so a bare
# `make` attempted to push to turkenh's Docker Hub account -- which a fork
# doesn't have write access to, and even on your own account a push should
# be a deliberate `make push_all`, not what a plain build invocation does.
.DEFAULT_GOAL := build_all

build:
	docker build -t $(USER)/${IMAGE}:${TAG} -f ${IMAGE}/Dockerfile .

push:
	docker push $(USER)/${IMAGE}:${TAG}

build_and_push: build push

build_all:
	IMAGE=ansible-managed-host $(MAKE) build
	IMAGE=ansible-tutorial $(MAKE) build

push_all:
	IMAGE=ansible-managed-host $(MAKE) push
	IMAGE=ansible-tutorial $(MAKE) push

all: build_all push_all
