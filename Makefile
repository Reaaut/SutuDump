TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SutuDump
SutuDump_FILES = Tweak.x
SutuDump_CFLAGS = -fobjc-arc -Wno-unused-function
SutuDump_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
