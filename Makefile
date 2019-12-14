.PHONY: checks test build
all: checks test build

setup:
	./scripts/install_ci_tools.sh

test:
	GO111MODULE=on go test -p 1 -v -count=1 -short ./...

integration:
	GO111MODULE=on go test -v -count=1 ./...

build: swagger-codegen test checks 
	GO111MODULE=on go build ./cmd/azbrowse

fmt:
	find . -name '*.go' | grep -v vendor | xargs gofmt -s -w

install:
	GO111MODULE=on go install ./cmd/azbrowse

checks:
	GO111MODULE=on golangci-lint run

ci-docker:
	docker run -it -e BUILD_NUMBER=999-localci -v /var/run/docker.sock:/var/run/docker.sock -v $(CURDIR):/go/src/github.com/lawrencegripper/azbrowse golang:1.11.5 bash -f /go/src/github.com/lawrencegripper/azbrowse/scripts/ci.sh

swagger-update:
	./scripts/update-swagger.sh
	
swagger-codegen:
	export GO111MODULE=on
	go run ./cmd/swagger-codegen/ 
	# Format the generated code
	gofmt -s -w internal/pkg/expanders/swagger-armspecs.generated.go
	gofmt -s -w internal/pkg/expanders/search.generated.go
	# Build the generated go files to check for any go build issues
	go build internal/pkg/expanders/swagger-armspecs.generated.go internal/pkg/expanders/swagger-armspecs.go internal/pkg/expanders/swagger.go internal/pkg/expanders/types.go internal/pkg/expanders/test_utils.go
	# Test the generated code initalizes
	go test -v internal/pkg/expanders/swagger-armspecs_test.go internal/pkg/expanders/swagger-armspecs.generated.go internal/pkg/expanders/swagger-armspecs.go internal/pkg/expanders/swagger.go internal/pkg/expanders/types.go

debug:
	GO111MODULE=on go build ./cmd/azbrowse &&  dlv exec ./azbrowse --headless --listen localhost:2345 --api-version 2

run: checks install
	azbrowse

fuzz: checks install
	azbrowse -fuzzer 5

fuzz-from: checks install
	azbrowse -fuzzer 5 -navigate ${node_id}

devcontainer:
ifdef DEVCONTAINER
	$(error This target can only be run outside of the devcontainer as it mounts files and this fails within a devcontainer. Don't worry all it needs is docker)
endif

	# Build the devcontainer
	docker build -f ./.devcontainer/Dockerfile ./.devcontainer -t devcontainer

# Used for locally running integration tests
devcontainer-integration: devcontainer
	docker run -v ${PWD}:${PWD} \
		--entrypoint /bin/bash \
		--workdir ${PWD} \
		-t devcontainer \
		-f ${PWD}/scripts/ci_integration_tests.sh

# Used by the build to create, test and publish
devcontainer-release: 
	# Note command mirrors required envs from host into container
	docker run -v ${PWD}:${PWD} \
		-e BUILD_NUMBER=${BUILD_NUMBER} \
		-e CIRCLECI=${CIRCLECI} \
		-e CIRCLE_PR_NUMBER=${CIRCLE_PR_NUMBER} \
		-e CIRCLE_BRANCH=${CIRCLE_BRANCH} \
		-e GITHUB_TOKEN=${GITHUB_TOKEN} \
		-e DOCKER_USERNAME=${DOCKER_USERNAME} \
		-e DOCKER_PASSWORD=${DOCKER_PASSWORD} \
		--entrypoint /bin/bash \
		--workdir ${PWD} \
		-t devcontainer \
		-c "${PWD}/scripts/ci_integration_tests.sh && ${PWD}/scripts/ci_release.sh"