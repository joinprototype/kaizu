APP_NAME := Kaizu
CONFIG ?= debug
APP := build/$(APP_NAME).app
# SwiftPM's default build system links without telling clang the SDK, so the
# binary is stamped with the deployment target as its SDK version and macOS runs
# Kaizu in pre-26 compatibility mode (old controls, WebKit ignores scrollbar-color).
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
SWIFT_FLAGS := -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$(SDK)"

.PHONY: build app run icon clean

build:
	swift build -c $(CONFIG) $(SWIFT_FLAGS)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" $(APP)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	mkdir -p $(APP)/Contents/Resources/Filters $(APP)/Contents/Resources/Scripts
	cp Resources/Filters/*.txt $(APP)/Contents/Resources/Filters/
	cp Resources/Scripts/*.js Resources/Scripts/*.txt $(APP)/Contents/Resources/Scripts/
	codesign --force --sign - $(APP)

run: app
	open $(APP)

# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset build/AppIcon-preview.png
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
