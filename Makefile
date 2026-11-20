ARCHS = arm64e
TARGET = iphone:clang:latest:17.0
IPHONEOS_DEPLOYMENT_TARGET = 17.0
THEOS_PACKAGE_SCHEME = rootless
DEB_ARCH = iphoneos-arm64e
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NeoStatus
NeoStatus_FILES = Tweak.xm NSConfig.m NSRuntimeProbe.m NSGlassPanel.m NSControlTile.m NSControlCenterViewController.m
NeoStatus_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NeoStatus_FRAMEWORKS = UIKit Foundation QuartzCore MediaPlayer AVFoundation CoreFoundation
NeoStatus_LIBRARIES = objc
NeoStatus_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(THEOS_PROJECT_DIR)/layout/Library/PreferenceLoader/Preferences/NeoStatusPrefs.plist" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(THEOS_PROJECT_DIR)/NeoStatus.plist" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/NeoStatus.plist"$(ECHO_END)

