 # Makefile to build dnsmasq blacklist
 	SHELL		= /bin/bash

 # Go parameters
	GOBUILD		= $(GOCMD) build
	GOCLEAN		= $(GOCMD) clean
	GOCMD		= go
	GOGEN		= $(GOCMD) generate
	GOGET		= $(GOCMD) get
	GOTEST		= $(GOCMD) test
	SRC			= $(shell find . -type f -name '*.go' -not -path "./vendor/*")

# Executable and package variables
	EXE			= update-dnsmasq
	PKG			= edgeos-dnsmasq-blacklist

# Executables
	GSED		= $(shell which gsed || which sed) -i.bak -e

# Environment variables
	AWS			= aws
	COPYRIGHT	= s/Copyright © 20../Copyright © $(shell date +"%Y")/g
	COVERALLS_TOKEN	\
				= W6VHc8ZFpwbfTzT3xoluEWbKkrsKT1w25
	# DATE=$(shell date -u '+%Y-%m-%d_%I:%M:%S%p')
	DATE		= $(shell date +'%FT%H%M%S')
	GIT			= $(shell git rev-parse --short HEAD)
	LIC			= license
	PAYLOAD 	= ./.payload
	README 		= README.md
	READMEHDR 	= README.header
	SCRIPTS 	= /config/scripts
	OLDVER 		= $(shell cat ./OLDVERSION)
	VER 		= $(shell cat ./VERSION)
	VERSIONS 	= s/$(PKG)_$(OLDVER)_/$(PKG)_$(VER)_/g
	BADGE 		= s/version-v$(OLDVER)-green.svg/version-v$(VER)-green.svg/g
	RELEASE 	= s/Release-v$(OLDVER)-green.svg/Release-v$(VER)-green.svg/g
	TAG 		= "v$(VER)"
	LDFLAGS 	= -X main.build=$(DATE) -X main.githash=$(GIT) -X main.version=$(VER)
	FLAGS 		= -s -w

.PHONY: all clean deps amd64 mips coverage copyright docs readme pkgs
all: clean deps amd64 mips coverage copyright docs readme pkgs

.PHONY: amd64 
amd64: generate
	$(eval LDFLAGS += -X main.architecture=amd64 -X main.hostOS=darwin)
	GOOS=darwin GOARCH=amd64 \
	$(GOOS) $(GOARCH) $(GOBUILD) -o $(EXE).amd64 \
	-ldflags "$(LDFLAGS) $(FLAGS)" -v

.PHONY: build
build: clean amd64 mips copyright docs readme 

.PHONY: cdeps 
cdeps: 
	dep status -dot | dot -T png | open -f -a /Applications/Preview.app

.PHONY: clean
clean:
	$(GOCLEAN)
	find . -name "$(EXE).*" -type f \
	-o -name debug -type f \
	-o -name "*.deb" -type f \
	-o -name debug.test -type f \
	-o -name "*.tgz" -type f \
	| xargs rm 

.PHONY: copyright
copyright:
	$(GSED) '$(COPYRIGHT)' $(README)
	$(GSED) '$(COPYRIGHT)' $(LIC)
	cp $(LIC) internal/edgeos/
	cp $(LIC) internal/regx/
	cp $(LIC) internal/tdata/

.PHONY: coverage 
coverage: 
	./testcoverage

.PHONY: dep-stat 
dep-stat: 
	dep status

.PHONY: deps
deps: 
	dep ensure -update -v

.PHONY: docs
docs: version readme
	./make_docs

.PHONY: generate
generate:
	cd internal/edgeos
	$(GOGEN)
	cd ../..
	cd internal/regx
	$(GOGEN)
	cd ../..	

.PHONY: mips
mips: mips64 mipsle

.PHONY: mips64
mips64: generate
	$(eval LDFLAGS += -X main.architecture=mips64 -X main.hostOS=linux)
	GOOS=linux GOARCH=mips64 $(GOBUILD) -o $(EXE).mips \
	-ldflags "$(LDFLAGS) $(FLAGS)" -v

.PHONY: mipsle
mipsle: generate
	$(eval LDFLAGS += -X main.architecture=mipsle -X main.hostOS=linux)
	GOOS=linux GOARCH=mipsle $(GOBUILD) -o $(EXE).mipsel \
	-ldflags "$(LDFLAGS) $(FLAGS)" -v

.PHONY: pkgs
pkgs: docs pkg-mips pkg-mipsel 

.PHONY: pkg-mips 
pkg-mips: deps mips coverage copyright docs readme
	cp $(EXE).mips $(PAYLOAD)$(SCRIPTS)/$(EXE) \
	&& ./make_deb $(EXE) mips

.PHONY: pkg-mipsel
pkg-mipsel: deps mipsle coverage copyright docs readme
	cp $(EXE).mipsel $(PAYLOAD)$(SCRIPTS)/$(EXE) \
	&& ./make_deb $(EXE) mipsel

.PHONY: readme 
readme: version
	cat README.header > README.md 
	godoc2md github.com/britannic/blacklist >> README.md

.PHONY: simplify
simplify:
	@gofmt -s -l -w $(SRC)

.PHONY: tags
tags:
	git push origin --tags

.PHONY: version
version:
	$(GSED) '$(BADGE)' $(READMEHDR)
	$(GSED) '$(RELEASE)' $(READMEHDR)
	$(GSED) '$(VERSIONS)' $(READMEHDR)
	cmp -s VERSION OLDVERSION || cp VERSION OLDVERSION

# git and miscellaneous upload info here
.PHONY: release
release: all commit push
	@echo Released $(TAG)

.PHONY: commit
commit:
	@echo Committing release $(TAG)
	git commit -am"Release $(TAG)"
	git tag $(TAG)

.PHONY: push
push:
	@echo Pushing release $(TAG) to master
	git push --tags
	git push

.PHONY: repo
repo:
	@echo Pushing repository $(TAG) to aws
	scp $(PKG)_$(VER)_*.deb aws:/tmp
	./aws.sh $(AWS) $(PKG)_$(VER)_ $(TAG)

.PHONY: upload
upload: pkgs
	scp $(PKG)_$(VER)_mips.deb dev1:/tmp
	scp $(PKG)_$(VER)_mipsel.deb er-x:/tmp
	scp $(PKG)_$(VER)_mips.deb ubnt:/tmp

.PHONY: z-aws
z-aws:
	./aws.sh $(AWS) $(PKG)_$(VER)_ $(TAG)