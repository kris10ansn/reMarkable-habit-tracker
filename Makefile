REMARKABLE_HOST ?= remarkable
APP_ID := habit-tracker
REMOTE_DIR := /home/root/xovi/exthome/appload/$(APP_ID)
RCC ?= rcc-qt5
BUILD_DIR := build

.PHONY: build deploy remove clean

build:
	mkdir -p $(BUILD_DIR)
	$(RCC) --binary -o $(BUILD_DIR)/resources.rcc application.qrc
	cp manifest.json icon.png $(BUILD_DIR)/

deploy: build
	ssh $(REMARKABLE_HOST) "mkdir -p $(REMOTE_DIR)"
	scp $(BUILD_DIR)/resources.rcc $(BUILD_DIR)/manifest.json $(BUILD_DIR)/icon.png $(REMARKABLE_HOST):$(REMOTE_DIR)/

remove:
	ssh $(REMARKABLE_HOST) "rm -rf $(REMOTE_DIR)"

clean:
	rm -rf $(BUILD_DIR)
