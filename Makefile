APP := build/Expire.app
BIN := .build/release/Expire

.PHONY: build test app run install zip clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Expire
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	open $(APP)

install: app
	rm -rf /Applications/Expire.app
	cp -R $(APP) /Applications/Expire.app

zip: app
	cd build && ditto -c -k --keepParent Expire.app Expire.zip

clean:
	rm -rf .build build
