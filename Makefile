SHELL=/bin/bash -o pipefail

# Application configuration
APP_NAME := learn-ruby
DOCKER_REPO := dxas90
REGISTRY := ghcr.io

# Version strategy using git tags
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_TAG := $(shell git describe --exact-match --abbrev=0 2>/dev/null || echo "")
COMMIT_HASH := $(shell git rev-parse --verify HEAD)
COMMIT_TIMESTAMP := $(shell date --date="@$$(git show -s --format=%ct)" --utc +%FT%T)

VERSION := $(shell git describe --tags --always --dirty)
VERSION_STRATEGY := commit_hash

ifdef GIT_TAG
	VERSION := $(GIT_TAG)
	VERSION_STRATEGY := tag
else
	ifeq (,$(findstring $(GIT_BRANCH),main master HEAD))
		ifneq (,$(patsubst release-%,,$(GIT_BRANCH)))
			VERSION := $(GIT_BRANCH)
			VERSION_STRATEGY := branch
		endif
	endif
endif

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RESET := \033[0m

.PHONY: help install build test clean run dev run-prod docker-build docker-run docker-compose docker-compose-down helm-deploy security lint version quick-start full-pipeline release

## Show this help message
help:
	@echo -e "$(BLUE)Available commands:$(RESET)"
	@awk '/^[a-zA-Z\-\_0-9%:\\ ]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = $$1; \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			gsub(":", "", helpCommand); \
			printf "  $(GREEN)%-20s$(RESET) %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

## Install dependencies
install:
	@echo -e "$(BLUE)Installing dependencies...$(RESET)"
	@bundle install
	@echo -e "$(GREEN)Dependencies installed successfully$(RESET)"

## Build the application (syntax check)
build: install
	@echo -e "$(BLUE)Building application...$(RESET)"
	@ruby -c app.rb
	@echo -e "$(GREEN)Ruby application syntax OK$(RESET)"

## Run tests
test: install
	@echo -e "$(BLUE)Running tests (RSpec)...$(RESET)"
	@bundle exec rspec --format documentation
	@echo -e "$(GREEN)RSpec tests completed$(RESET)"

## Run Helm unit tests
helm-test:
	@echo -e "$(BLUE)Running Helm unit tests...$(RESET)"
	@helm lint k8s/learn-ruby || exit 1
	@helm unittest k8s/learn-ruby --output-type JUnit --output-file k8s/learn-ruby/test-results.xml || exit 1
	@echo -e "$(GREEN)Helm unit tests completed$(RESET)"

## Clean build artifacts
clean:
	@echo -e "$(BLUE)Cleaning build artifacts...$(RESET)"
	rm -rf .bundle vendor/bundle log/*.log tmp/*
	@if command -v docker > /dev/null 2>&1; then \
		echo -e "$(BLUE)Cleaning Docker artifacts...$(RESET)"; \
		docker system prune -f || echo -e "$(YELLOW)Warning: Could not clean Docker artifacts$(RESET)"; \
	else \
		echo -e "$(YELLOW)Docker not available, skipping Docker cleanup$(RESET)"; \
	fi

## Run the application locally
run: install
	@echo -e "$(BLUE)Starting application locally...$(RESET)"
	@bundle exec ruby app.rb

## Run the application in development mode
dev: install
	@echo -e "$(BLUE)Starting application in development mode...$(RESET)"
	@RACK_ENV=development bundle exec rackup config.ru

## Run with production profile
run-prod: install
	@echo -e "$(BLUE)Starting application with production profile...$(RESET)"
	@RACK_ENV=production bundle exec puma config.ru -C puma.rb

## Build Docker image
docker-build:
	@echo -e "$(BLUE)Building Docker image...$(RESET)"
	docker build --target production -t $(APP_NAME):$(VERSION) .
	docker tag $(APP_NAME):$(VERSION) $(APP_NAME):latest

## Run Docker container
docker-run:
	@echo -e "$(BLUE)Running Docker container...$(RESET)"
	docker run -it --rm -p 4567:4567 --name $(APP_NAME) $(APP_NAME):$(VERSION)

## Start application with Docker Compose
docker-compose:
	@echo -e "$(BLUE)Starting services with Docker Compose...$(RESET)"
	@if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then \
		docker-compose up --build; \
	else \
		echo -e "$(YELLOW)No docker-compose.yml file found$(RESET)"; \
		echo -e "$(YELLOW)Use 'make docker-run' to run the container directly$(RESET)"; \
	fi

## Stop Docker Compose services
docker-compose-down:
	@echo -e "$(BLUE)Stopping Docker Compose services...$(RESET)"
	@if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then \
		docker-compose down -v; \
	else \
		echo -e "$(YELLOW)No docker-compose.yml file found$(RESET)"; \
	fi

## Deploy using Helm
helm-deploy:
	@echo -e "$(BLUE)Deploying with Helm...$(RESET)"
	helm upgrade --install $(APP_NAME) ./k8s/learn-ruby

## Run security scan
security:
	@echo -e "$(BLUE)Running security scan...$(RESET)"
	@if command -v bundle-audit > /dev/null 2>&1; then \
		bundle-audit check --update; \
	else \
		echo -e "$(YELLOW)bundle-audit not installed$(RESET)"; \
		echo -e "$(YELLOW)Install with: gem install bundler-audit$(RESET)"; \
	fi

## Run code quality checks
lint: install
	@echo -e "$(BLUE)Running linters...$(RESET)"
	@ruby -c app.rb
	@ruby -c config.ru

## Show version information
version:
	@echo -e "$(BLUE)Version Information:$(RESET)"
	@echo -e "Version: $(VERSION)"
	@echo -e "Strategy: $(VERSION_STRATEGY)"
	@echo -e "Git Tag: $(GIT_TAG)"
	@echo -e "Git Branch: $(GIT_BRANCH)"
	@echo -e "Commit Hash: $(COMMIT_HASH)"
	@echo -e "Commit Timestamp: $(COMMIT_TIMESTAMP)"

## Health check
health-check:
	@echo -e "$(BLUE)Performing health check...$(RESET)"
	@curl -s http://localhost:4567/healthz | jq . || echo -e "$(RED)Health check failed$(RESET)"

## Update dependencies
update:
	@echo -e "$(BLUE)Updating dependencies...$(RESET)"
	@bundle update

## Check for outdated packages
outdated:
	@echo -e "$(BLUE)Checking for outdated packages...$(RESET)"
	@bundle outdated

## Quick start - install, test, and run locally
quick-start: clean install test run

## Full pipeline - test, build, and deploy locally
full-pipeline: test security docker-build docker-compose

## Release - tag and build for release
release:
	@echo -e "$(BLUE)Preparing release $(VERSION)...$(RESET)"
	git tag -a v$(VERSION) -m "Release version $(VERSION)"
	$(MAKE) docker-build
	@echo -e "$(GREEN)Release $(VERSION) ready!$(RESET)"
