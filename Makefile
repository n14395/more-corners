APP_NAME = MoreCorners
BUILD_DIR = .build/release
APP = $(APP_NAME).app

.PHONY: build app dmg run icon clean

build:
	swift build -c release

app:
	./build.sh app

dmg:
	./build.sh dmg

icon:
	swift scripts/make-icon.swift

run:
	./build.sh run

clean:
	rm -rf .build $(APP) $(APP_NAME)*.dmg
