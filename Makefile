APP_NAME = MoreCorners
BUILD_DIR = .build/release
APP = $(APP_NAME).app

.PHONY: build app run clean

build:
	swift build -c release

app:
	./build.sh

icon:
	swift scripts/make-icon.swift

run:
	./build.sh run

clean:
	rm -rf .build $(APP)
