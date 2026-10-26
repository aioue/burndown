APP := build/Burndown.app
BIN := .build/release/Burndown

.PHONY: build test app run install zip clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Burndown
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	open $(APP)

install: app
	rm -rf /Applications/Burndown.app
	cp -R $(APP) /Applications/Burndown.app

zip: app
	cd build && ditto -c -k --keepParent Burndown.app Burndown.zip

clean:
	rm -rf .build build
