ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MaxKeys
MaxKeys_FILES = Tweak.xm
MaxKeys_CFLAGS = -fobjc-arc
MaxKeys_FRAMEWORKS = UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
