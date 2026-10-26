.PHONY: build test app run install release icon clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

run: app
	-pkill -x Quarry
	open build/Quarry.app

install: app
	-pkill -x Quarry
	rm -rf /Applications/Quarry.app
	mv build/Quarry.app /Applications/  # move, so Spotlight sees one copy
	open /Applications/Quarry.app

# Zipped, signed app for a GitHub release: build/Quarry-<version>.zip
release: app
	ditto -c -k --keepParent build/Quarry.app build/Quarry-$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist).zip

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
