APP_NAME := GlasshouseTray
APP      := build/$(APP_NAME).app
BIN_DIR   = $(shell swift build -c release --arch arm64 --show-bin-path)

# Accessibility permission is tied to the code signature. Signing with a
# stable identity keeps the grant across rebuilds; ad-hoc ("-") does not.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development|Developer ID Application/ { print $$2; exit }')

.PHONY: all build app run install clean

all: app

build:
	swift build -c release --arch arm64

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --options runtime --sign "$(or $(SIGN_IDENTITY),-)" "$(APP)"

run: app
	open "$(APP)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/

clean:
	rm -rf .build build
