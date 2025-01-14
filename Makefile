DOCKERFILES=$(shell find * -type f -name Dockerfile)
NAMES=$(subst /,\:,$(subst /Dockerfile,,$(DOCKERFILES)))
REGISTRY?=r.in.philpep.org
IMAGES=$(addprefix $(subst :,\:,$(REGISTRY))/,$(NAMES))
DEPENDS=.depends.mk
MAKEFLAGS += -rR

GO=$(shell command -v go)
GOPATH_BIN=$(shell test -n "$(GO)" && $(GO) env GOPATH)/bin

help:
	@echo "A smart Makefile for your dockerfiles"
	@echo ""
	@echo "Read all Dockerfile within the current directory and generate dependendies automatically."
	@echo ""
	@echo "make duuh             ; installs tool duuh (unattended upgrades, requires "go" compiler)"
	@echo "make ls               ; lists all images"
	@echo "make all              ; build all images"
	@echo "make nginx            ; build nginx image"
	@echo "make push all         ; build and push all images"
	@echo "make push nginx       ; build and push nginx image"
	@echo "make run nginx        ; build and run nginx image (for testing)"
	@echo "make exec nginx       ; build and start interactive shell in nginx image (for debugging)"
	@echo "make checkrebuild all ; build and check if image has update availables (using https://github.com/philpep/duuh)"q
	@echo "                        and rebuild with --no-cache is image has updates"
	@echo "make pull-base        ; pull base images from docker hub used to bootstrap other images"
	@echo "make ci               ; alias to make pull-base checkrebuild push all"
	@echo ""
	@echo "You can chain actions, typically in CI environment you want make checkrebuild push all"
	@echo "which rebuild and push only images having updates availables."

.PHONY: all ls clean push pull run exec check checkrebuild pull-base ci $(NAMES) $(IMAGES)

duuh:
	@test -n "$(GO)" || (>&2 echo "installation of '$@' requires 'go' command to be installed in PATH" && exit 1)
	@$(GO) get -u github.com/philpep/duuh/... \
	&& echo $(GOPATH_BIN)/duuh --help \
	&& $(GOPATH_BIN)/duuh --help

ls:
	@echo "$(shell tput smul)Available images$(shell tput sgr0):" \
	&& echo $(NAMES) \
	 | tr ' ' '\t' \
	 | column -x

all: $(NAMES)

clean:
	rm -f $(DEPENDS)

pull-base:
	# used by debian:buster-slim
	docker pull debian:buster-slim
	# used by keycloak
	docker pull jboss/keycloak:12.0.4
#	# imago
#	docker pull philpep/imago

ci:
	$(MAKE) pull-base checkrebuild push all

.PHONY: $(DEPENDS)
$(DEPENDS): $(DOCKERFILES)
	@grep '^FROM \$$REGISTRY/' $(DOCKERFILES) | \
		awk -F '/Dockerfile:FROM \\$$REGISTRY/' '{ print $$1 " " $$2 }' | \
		sed 's@[:/]@\\:@g' | awk '{ print "$(subst :,\\:,$(REGISTRY))/" $$1 ": " "$(subst :,\\:,$(REGISTRY))/" $$2 }' > $@

sinclude $(DEPENDS)

$(NAMES): %: $(REGISTRY)/%
ifeq (push,$(filter push,$(MAKECMDGOALS)))
	docker push $<
endif
ifeq (run,$(filter run,$(MAKECMDGOALS)))
	docker run --rm -it $<
endif
ifeq (exec,$(filter exec,$(MAKECMDGOALS)))
	docker run --entrypoint sh --rm -it $<
endif
ifeq (check,$(filter check,$(MAKECMDGOALS)))
	duuh $<
endif

$(IMAGES): %:
ifeq (pull,$(filter pull,$(MAKECMDGOALS)))
	docker pull $@
else
	docker build --build-arg REGISTRY=$(REGISTRY) -t $@ $(subst :,/,$(subst $(REGISTRY)/,,$@))
endif
ifeq (checkrebuild,$(filter checkrebuild,$(MAKECMDGOALS)))
	which duuh >/dev/null || (>&2 echo "checkrebuild require duuh command to be installed in PATH" && exit 1)
	duuh $@ || (docker build --build-arg REGISTRY=$(REGISTRY) --no-cache -t $@ $(subst :,/,$(subst $(REGISTRY)/,,$@)) && duuh $@)
endif
