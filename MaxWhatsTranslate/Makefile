ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MaxWhatsTranslate
MaxWhatsTranslate_FILES = Tweak.xm ConversationTranslator.m Translator.m
MaxWhatsTranslate_CFLAGS = -fobjc-arc
MaxWhatsTranslate_FRAMEWORKS = UIKit Foundation NaturalLanguage
include $(THEOS_MAKE_PATH)/tweak.mk
