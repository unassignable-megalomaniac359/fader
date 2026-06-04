# Developer entry points. Releases and the site deploy run in GitHub Actions
# (.github/workflows); nothing here needs credentials.

XCODEPROJ := Fader.xcodeproj
SCHEME    := Fader

.PHONY: gen build test lint format run clean icon

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		CODE_SIGNING_ALLOWED=NO build

test: gen
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		CODE_SIGNING_ALLOWED=NO test

lint:
	swiftformat --lint .
	swiftlint --strict

format:
	swiftformat .

run: build
	open "$$(xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		-showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $$3}')/Fader.app"

clean:
	rm -rf build dist $(XCODEPROJ)

# Regenerate the app icon from scripts/generate-icon.swift.
icon:
	swift scripts/generate-icon.swift /tmp/fader-icon-1024.png
	rm -rf /tmp/fader.iconset && mkdir -p /tmp/fader.iconset
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size /tmp/fader-icon-1024.png --out /tmp/fader.iconset/icon_$${size}x$${size}.png > /dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) /tmp/fader-icon-1024.png --out /tmp/fader.iconset/icon_$${size}x$${size}@2x.png > /dev/null; \
	done
	iconutil -c icns /tmp/fader.iconset -o Fader/Resources/Fader.icns
