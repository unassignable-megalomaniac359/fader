# Developer entry points. Releases and the site deploy run in GitHub Actions
# (.github/workflows); nothing here needs credentials.

XCODEPROJ := Fader.xcodeproj
SCHEME    := Fader

# TCC keys permission grants to the signing identity; unsigned (ad-hoc)
# debug builds get pinned to the binary hash and re-prompt on every
# rebuild. Sign with the local Developer ID when present; contributors
# without the certificate fall back to no signing.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -o '"Developer ID Application: [^"]*"' | head -1)
ifeq ($(SIGN_ID),)
SIGN_FLAGS := CODE_SIGNING_ALLOWED=NO
else
SIGN_FLAGS := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=$(SIGN_ID)
endif

.PHONY: gen build test lint format run clean icon og menubar-icon

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug \
		$(SIGN_FLAGS) build

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

# Regenerate the menu bar template icon (1x + 2x).
menubar-icon:
	swift scripts/generate-menubar-icon.swift Fader/Resources

# Regenerate the site's Open Graph preview card.
og:
	swift scripts/generate-og.swift site/og.png
	pngquant --force --quality 65-85 --output site/og.png site/og.png
