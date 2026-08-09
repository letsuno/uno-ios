PROJECT := UnoClient.xcodeproj
SCHEME := UnoClient

BUILD_CONFIGURATION ?= Release
BUILD_DESTINATION ?= generic/platform=iOS
DERIVED_DATA_PATH ?= $(CURDIR)/DerivedData
TEST_CONFIGURATION ?= Debug
TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
VERSION_CONFIGURATION := Configuration/Shared.xcconfig

ARCHIVE_PATH ?= $(CURDIR)/build/UnoClient.xcarchive
EXPORT_PATH ?= $(CURDIR)/build/export
EXPORT_OPTIONS_PLIST ?= $(CURDIR)/build/ExportOptions.plist

# Signing stays unset by default so a local archive keeps the project's automatic
# signing. Distribution builds pass the identity in from the environment holding
# the certificate.
CODE_SIGN_STYLE ?=
CODE_SIGN_IDENTITY ?=
DEVELOPMENT_TEAM ?=
PROVISIONING_PROFILE_SPECIFIER ?=
CURRENT_PROJECT_VERSION ?=

ARCHIVE_SETTINGS = \
	$(if $(CODE_SIGN_STYLE),CODE_SIGN_STYLE="$(CODE_SIGN_STYLE)") \
	$(if $(CODE_SIGN_IDENTITY),CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)") \
	$(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)") \
	$(if $(PROVISIONING_PROFILE_SPECIFIER),PROVISIONING_PROFILE_SPECIFIER="$(PROVISIONING_PROFILE_SPECIFIER)") \
	$(if $(CURRENT_PROJECT_VERSION),CURRENT_PROJECT_VERSION="$(CURRENT_PROJECT_VERSION)")

RESULT_BUNDLE_ARGUMENT = $(if $(RESULT_BUNDLE_PATH),-resultBundlePath "$(RESULT_BUNDLE_PATH)")

.PHONY: analyze archive build export format-check ipa project-check quality release-version show-settings test

quality: format-check project-check

format-check:
	xcrun swift-format lint \
		--configuration .swift-format \
		--recursive \
		--parallel \
		--strict \
		UnoClient \
		UnoClientTests

project-check:
	plutil -lint Support/Info.plist
	plutil -lint UnoClient/PrivacyInfo.xcprivacy
	plutil -lint UnoClient/UnoClient.entitlements
	plutil -lint UnoClient.xcodeproj/project.pbxproj
	@settings="$$(xcodebuild -showBuildSettings \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(BUILD_CONFIGURATION)" \
		-destination '$(BUILD_DESTINATION)' 2>/dev/null)"; \
	marketing_version="$$(printf '%s\n' "$$settings" | awk '/^[[:space:]]+MARKETING_VERSION = / { print $$3; exit }')"; \
	swift_version="$$(printf '%s\n' "$$settings" | awk '/^[[:space:]]+SWIFT_VERSION = / { print $$3; exit }')"; \
	configured_version="$$( $(MAKE) --no-print-directory release-version )"; \
	test "$$marketing_version" = "$$configured_version"; \
	test "$$swift_version" = "6"

release-version:
	@set -e; \
	version="$$(awk -F '=' ' \
		/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ { \
			value = $$2; \
			sub(/\/\/.*/, "", value); \
			gsub(/[[:space:]]/, "", value); \
			print value; \
			count++; \
		} \
		END { if (count != 1) exit 1 } \
	' "$(VERSION_CONFIGURATION)")"; \
	printf '%s\n' "$$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; \
	printf '%s\n' "$$version"

show-settings:
	xcodebuild -showBuildSettings \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(BUILD_CONFIGURATION)" \
		-destination '$(BUILD_DESTINATION)'

build:
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(BUILD_CONFIGURATION)" \
		-destination '$(BUILD_DESTINATION)' \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		CODE_SIGNING_ALLOWED=NO

analyze:
	xcodebuild analyze \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(BUILD_CONFIGURATION)" \
		-destination '$(BUILD_DESTINATION)' \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		CODE_SIGNING_ALLOWED=NO

archive:
	xcodebuild clean archive \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(BUILD_CONFIGURATION)" \
		-destination '$(BUILD_DESTINATION)' \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		-archivePath "$(ARCHIVE_PATH)" \
		$(ARCHIVE_SETTINGS)

export:
	xcodebuild -exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath "$(EXPORT_PATH)" \
		-exportOptionsPlist "$(EXPORT_OPTIONS_PLIST)"

ipa: archive
	$(MAKE) export

test:
	xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(TEST_CONFIGURATION)" \
		-destination '$(TEST_DESTINATION)' \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		$(RESULT_BUNDLE_ARGUMENT) \
		CODE_SIGNING_ALLOWED=NO
