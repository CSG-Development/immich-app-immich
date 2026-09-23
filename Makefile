dev:
	@printf "This command has been removed. Please use:\n\n    mise dev          # or mise //:dev from another directory\n\n" >&2 && exit 1

dev-down:
	@printf "This command has been removed. Please use:\n\n    mise dev-down          # or mise //:dev-down from another directory\n\n" >&2 && exit 1

dev-update:
	@printf "This command has been removed. Please use:\n\n    mise dev-update          # or mise //:dev-update from another directory\n\n" >&2 && exit 1

dev-scale:
	@printf "This command has been removed. Please use:\n\n    mise dev-scale          # or mise //:dev-scale from another directory\n\n" >&2 && exit 1

dev-docs:
	npm --prefix docs run start

.PHONY: e2e
e2e:
	@printf "This command has been removed. Please use:\n\n    mise e2e          # or mise //:e2e from another directory\n\n" >&2 && exit 1

e2e-dev:
	@printf "This command has been removed. Please use:\n\n    mise e2e-dev          # or mise //:e2e-dev from another directory\n\n" >&2 && exit 1

e2e-update:
	@printf "This command has been removed. Please use:\n\n    mise e2e-update          # or mise //:e2e-update from another directory\n\n" >&2 && exit 1

e2e-down:
	@printf "This command has been removed. Please use:\n\n    mise e2e-down          # or mise //:e2e-down from another directory\n\n" >&2 && exit 1

prod:
	@printf "This command has been removed. Please use:\n\n    mise prod          # or mise //:prod from another directory\n\n" >&2 && exit 1

prod-down:
	@printf "This command has been removed. Please use:\n\n    mise prod-down          # or mise //:prod-down from another directory\n\n" >&2 && exit 1

prod-scale:
	@printf "This command has been removed. Please use:\n\n    mise prod-scale          # or mise //:prod-scale from another directory\n\n" >&2 && exit 1

.PHONY: open-api
open-api:
	@printf "This command has been removed. Please use:\n\n    mise open-api          # or mise //:open-api from another directory\n\n" >&2 && exit 1

sql:
	@printf "This command has been removed. Please use:\n\n    mise sql               # or mise //:sql from another directory\n\n" >&2 && exit 1

IMAGE_EDITOR_WEB_APP_DIR = ./image_editor_web_app
IMAGE_EDITOR_WEB_BUILD_DIR = $(IMAGE_EDITOR_WEB_APP_DIR)/build/web
IMAGE_EDITOR_WEB_STATIC_DIR = ./web/static/flutter

.PHONY: build-image-editor-web-app
build-image-editor-web-app:
	cd $(IMAGE_EDITOR_WEB_APP_DIR) && flutter pub get
	cd $(IMAGE_EDITOR_WEB_APP_DIR) && flutter build web
	rm -rf $(IMAGE_EDITOR_WEB_STATIC_DIR)
	mkdir -p ./web/static
	cp -R $(IMAGE_EDITOR_WEB_BUILD_DIR) $(IMAGE_EDITOR_WEB_STATIC_DIR)

renovate:
  LOG_LEVEL=debug pnpm exec renovate --platform=local --repository-cache=reset

# Include .env file if it exists
-include docker/.env

MODULES = e2e server web cli sdk docs .github

test-e2e:
	@printf "This command has been removed. Please use:\n\n    mise //e2e:test               # or mise //e2e:test-web for web tests, respectively\n\n" >&2 && exit 1

clean:
	@printf "This command has been removed. Please use:\n\n    mise clean               # or mise //:clean from another directory\n\n" >&2 && exit 1
