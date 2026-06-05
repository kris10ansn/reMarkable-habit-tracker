REMARKABLE_HOST ?= remarkable
APP_ID := habit-tracker
REMOTE_DIR := /home/root/xovi/exthome/appload/$(APP_ID)
RCC ?= rcc-qt5
QMLLINT ?= qmllint-qt5
QML_IMPORT_PATH ?= /usr/lib/qt/qml
BUILD_DIR := build
QML_FILES := $(shell find ui -name '*.qml')

.PHONY: build deploy remove clean lint

build:
	mkdir -p $(BUILD_DIR)
	$(RCC) --binary -o $(BUILD_DIR)/resources.rcc application.qrc
	cp manifest.json icon.png $(BUILD_DIR)/

lint:
	@command -v qmllint-qt5 >/dev/null 2>&1 && qmllint-qt5 src/*.qml src/components/*.qml || echo "qmllint-qt5 not installed; skipping"

deploy: build
	ssh $(REMARKABLE_HOST) "mkdir -p $(REMOTE_DIR)"
	scp $(BUILD_DIR)/resources.rcc $(BUILD_DIR)/manifest.json $(BUILD_DIR)/icon.png $(REMARKABLE_HOST):$(REMOTE_DIR)/

remove:
	ssh $(REMARKABLE_HOST) "rm -rf $(REMOTE_DIR)"

clean:
	rm -rf $(BUILD_DIR)

lint:
	$(QMLLINT) -I $(QML_IMPORT_PATH) $(QML_FILES)
