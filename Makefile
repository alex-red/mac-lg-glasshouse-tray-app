APP_NAME := GlasshouseTray
APP      := build/$(APP_NAME).app
BIN_DIR   = $(shell swift build -c release --arch arm64 --show-bin-path)

# Set by the release workflow from the tag (e.g. 0.2.0). When empty, the
# version in Resources/Info.plist is used as is.
VERSION ?=
ZIP      = build/$(APP_NAME)-$(or $(VERSION),dev).zip

# Accessibility permission is tied to the code signature. Signing with a
# stable identity keeps the grant across rebuilds; ad-hoc ("-") does not.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Developer ID Application|Apple Development/ { print $$2; exit }')
# The release workflow adds --timestamp, which notarization requires.
CODESIGN_FLAGS ?=

.PHONY: all build app zip run install clean

all: app

build:
	swift build -c release --arch arm64

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
ifneq ($(VERSION),)
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(VERSION)" \
		"$(APP)/Contents/Info.plist"
endif
	codesign --force --options runtime $(CODESIGN_FLAGS) --sign "$(or $(SIGN_IDENTITY),-)" "$(APP)"

# Zips the already-built app (run `make app` first), e.g. after stapling.
zip:
	rm -f "$(ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(ZIP)"
	@echo "$(ZIP)"

run: app
	open "$(APP)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/

clean:
	rm -rf .build build
