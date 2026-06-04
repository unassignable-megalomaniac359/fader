# Developer entry points. Releases and the site deploy run in GitHub Actions
# (.github/workflows); nothing here needs credentials.

XCODEPROJ := Fader.xcodeproj
SCHEME    := Fader

.PHONY: gen build test lint format run clean

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
