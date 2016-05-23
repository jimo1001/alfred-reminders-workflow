name = alfred-reminders-workflow
version = 0.4

all: package

build:
	xcodebuild

package: build
	mkdir -p build/_package/bin
	cp -rv *.png LICENSE Makefile README.md aw-input aw-input.xcodeproj info.plist scripts build/_package/
	cp -v build/Release/aw-input build/_package/bin/
	cd build/_package && zip -r ../$(name)-$(version).alfredworkflow *

clean:
	rm -frv build
