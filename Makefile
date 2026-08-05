.PHONY: run run-release build-android build-ios pub-get test

ENV_FILE := env.json

run: ## flutter run (debug) con env.json cargado — mapa estático funcionando
	flutter run --dart-define-from-file=$(ENV_FILE)

run-release: ## flutter run en modo release, con env.json
	flutter run --release --dart-define-from-file=$(ENV_FILE)

build-android: ## Bundle para Google Play, con env.json (obligatorio: sin esto la key queda vacía en el bundle subido)
	flutter build appbundle --release --dart-define-from-file=$(ENV_FILE)

build-ios: ## Build para App Store, con env.json
	flutter build ios --release --dart-define-from-file=$(ENV_FILE)

pub-get:
	flutter pub get

test:
	flutter test
