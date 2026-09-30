.PHONY: run run-release build-android build-ios build-ipa upload-symbols pub-get test

ENV_FILE := env.json
# D3: builds de release con el Dart ofuscado. Los símbolos quedan en
# SYMBOLS_DIR y hay que subirlos a Crashlytics (`make upload-symbols`) para
# que los stack traces sigan legibles. Guardarlos por versión: sin ellos no
# se puede desofuscar un crash de esa build nunca más.
# Un directorio por plataforma: la herramienta de Crashlytics procesa todo
# el directorio y falla con los símbolos de la otra plataforma.
SYMBOLS_DIR := build/symbols
RELEASE_FLAGS := --release --dart-define-from-file=$(ENV_FILE) --obfuscate
ANDROID_APP_ID := 1:1011373106222:android:f5f0573a658779ccf56bbf
IOS_APP_ID := 1:1011373106222:ios:040b03b6936cb4a9f56bbf

run: ## flutter run (debug) con env.json cargado — mapa estático funcionando
	flutter run --dart-define-from-file=$(ENV_FILE)

run-release: ## flutter run en modo release, con env.json
	flutter run --release --dart-define-from-file=$(ENV_FILE)

build-android: ## Bundle para Google Play, con env.json (obligatorio: sin esto la key queda vacía en el bundle subido)
	flutter build appbundle $(RELEASE_FLAGS) --split-debug-info=$(SYMBOLS_DIR)/android

build-ios: ## Build para App Store, con env.json
	flutter build ios $(RELEASE_FLAGS) --split-debug-info=$(SYMBOLS_DIR)/ios

build-ipa: ## .ipa para App Store Connect, con env.json
	flutter build ipa $(RELEASE_FLAGS) --split-debug-info=$(SYMBOLS_DIR)/ios

upload-symbols: ## Sube los símbolos de Dart de la última build a Crashlytics (Android e iOS)
	firebase crashlytics:symbols:upload --app=$(ANDROID_APP_ID) $(SYMBOLS_DIR)/android
	# iOS: Crashlytics desofusca con los dSYM del archive (el comando de arriba
	# es solo para Android). build/symbols/ios se guarda para `flutter symbolize`.
	ios/Pods/FirebaseCrashlytics/upload-symbols -gsp ios/Runner/GoogleService-Info.plist -p ios build/ios/archive/Runner.xcarchive/dSYMs

pub-get:
	flutter pub get

test:
	flutter test
