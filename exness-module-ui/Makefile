export THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = ExnessMobile

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ExnessModuleUI

ExnessModuleUI_FILES = \
	Tweak.xm \
	Sources/MUIModule.m \
	Sources/MUIConfigStore.m \
	Sources/MUIScreenCandidate.m \
	Sources/MUIScreenLayoutStore.m \
	Sources/MUIScreenOverlayManager.m \
	Sources/MUIScreenEditorViewController.m \
	Sources/MUIRuntime.m \
	Sources/MUIPreviewView.m \
	Sources/MUIDesignerViewController.m

ExnessModuleUI_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
ExnessModuleUI_FRAMEWORKS = UIKit Foundation PhotosUI UniformTypeIdentifiers

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 ExnessMobile || true"
