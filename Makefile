APP := build/Burndown.app
BIN := .build/release/Burndown

.PHONY: build test app icon docs-images run install zip clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Burndown
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)

icon:
	swift Scripts/make-icon.swift

# README images: the app renders its own views with demo data (throwaway home, real state untouched).
docs-images: build
	mkdir -p docs/images
	$(BIN) --render-docs docs/images
	tmp=$$(mktemp -d) && iconutil --convert iconset --output $$tmp/AppIcon.iconset Resources/AppIcon.icns \
		&& cp $$tmp/AppIcon.iconset/icon_128x128@2x.png docs/images/icon.png && rm -rf $$tmp

run: app
	open $(APP)

install: app
	rm -rf /Applications/Burndown.app
	cp -R $(APP) /Applications/Burndown.app

zip: app
	cd build && ditto -c -k --keepParent Burndown.app Burndown.zip

clean:
	rm -rf .build build
