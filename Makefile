ARCHS = arm64
ASTERHAND_ENV ?= rootless
ifeq ($(ASTERHAND_ENV),rootful)
TARGET = iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME =
THEOS_LAYOUT_DIR = $(CURDIR)/packaging-rootful
ADDITIONAL_CFLAGS += -DPC_ROOTFUL=1
else
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
THEOS_LAYOUT_DIR = $(CURDIR)/packaging
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PocketCodex
PocketCodex_FILES = $(wildcard Sources/*.m) Sources/PCProcess.c
PocketCodex_CFLAGS = -Wall -Wextra -Wno-unused-parameter -ISources
PocketCodex_OBJCFLAGS = -fobjc-arc
PocketCodex_FRAMEWORKS = UIKit Foundation Security CoreGraphics WebKit PhotosUI UniformTypeIdentifiers UserNotifications AVFoundation Speech Intents IntentsUI CallKit
PocketCodex_RESOURCE_FILES = Resources/localizations.json Resources/user-guide.json Resources/tools.json Resources/screen-tools.json $(wildcard Resources/*.png) $(wildcard Resources/Icons/*.png)
PocketCodex_RESOURCE_DIRS = $(wildcard Resources/*.lproj) Resources/Guide
PocketCodex_INFOPLIST = Resources/Info.plist
PocketCodex_CODESIGN_FLAGS = -Sentitlements.plist
PocketCodex_INSTALL_PATH = /Applications
PocketCodex_LDFLAGS = -Wl,-headerpad,0x1000

include $(THEOS_MAKE_PATH)/application.mk

# Cross-platform canonical packaging uses scripts/package_app.py after signing.
