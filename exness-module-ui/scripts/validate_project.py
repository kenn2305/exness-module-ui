from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "Makefile",
    "control",
    "ExnessModuleUI.plist",
    "Tweak.xm",
    "Sources/MUIRuntime.m",
    "Sources/MUIDesignerViewController.m",
    "Sources/MUIScreenEditorViewController.m",
    "Sources/MUIScreenOverlayManager.m",
    "Sources/MUIScreenLayoutStore.m",
    "layout/DEBIAN/postinst",
    "layout/DEBIAN/prerm",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


for relative in REQUIRED:
    if not (ROOT / relative).is_file():
        fail(f"missing required file: {relative}")

makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
for required in (
    "THEOS_PACKAGE_SCHEME = rootless",
    "ARCHS = arm64 arm64e",
    "TARGET = iphone:clang:latest:15.0",
    "INSTALL_TARGET_PROCESSES = ExnessMobile",
):
    if required not in makefile:
        fail(f"Makefile is missing: {required}")

control = (ROOT / "control").read_text(encoding="utf-8")
fields = {}
for line in control.splitlines():
    if ":" in line:
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
for field in ("Package", "Name", "Version", "Architecture", "Depends"):
    if not fields.get(field):
        fail(f"control is missing field: {field}")
if fields["Package"] != "com.vietanh.exnessmoduleui":
    fail("unexpected package identifier")
if fields["Architecture"] != "iphoneos-arm64":
    fail("rootless package architecture must be iphoneos-arm64")
if "firmware (>= 15.0)" not in fields["Depends"] or "firmware (<< 17.0)" not in fields["Depends"]:
    fail("control must restrict installation to iOS 15-16")

raw_filter = (ROOT / "ExnessModuleUI.plist").read_text(encoding="utf-8")
if "com.exness.mobile" not in raw_filter or "ExnessMobile" not in raw_filter:
    fail("injection filter does not target the real Exness bundle and executable")

tweak = (ROOT / "Tweak.xm").read_text(encoding="utf-8")
for invariant in ("%hook UIWindow", "sendEvent", "prepareForPossibleScreenTransition", "viewHierarchyDidChange"):
    if invariant not in tweak:
        fail(f"generic host-app hook is missing: {invariant}")

runtime = (ROOT / "Sources/MUIRuntime.m").read_text(encoding="utf-8")
for invariant in (
    "observeWindow",
    "numberOfTouchesRequired = 3",
    "selectedNavigationMarkerInView",
    "completePossibleScreenTransition",
    "restoreBaselineWithoutSaving",
    "refreshCurrentScreenLayout",
):
    if invariant not in runtime:
        fail(f"runtime safety path is missing: {invariant}")

designer = (ROOT / "Sources/MUIDesignerViewController.m").read_text(encoding="utf-8")
if "PHPickerViewController" not in designer or "moveRowAtIndexPath" not in designer:
    fail("native module designer is incomplete")

screen_editor = (ROOT / "Sources/MUIScreenEditorViewController.m").read_text(encoding="utf-8")
for feature in (
    "addTapped",
    "handlePanned",
    "handlePinched",
    "Choose from Photos",
    "linkTapped",
    "addCustomElement",
    "scaleSliderChanged",
    "canvasPanned",
    "maximumValue = 50.0",
    "natural_w",
    "saveOriginalImage",
):
    if feature not in screen_editor:
        fail(f"screen editor is missing feature: {feature}")

overlay_manager = (ROOT / "Sources/MUIScreenOverlayManager.m").read_text(encoding="utf-8")
for invariant in (
    "sendActionsForControlEvents",
    "removeOverlayAndRestoreOriginalsForRootView",
    "scanCandidatesInRootView",
    "presentActionPanelForElement",
):
    if invariant not in overlay_manager:
        fail(f"screen overlay manager is missing invariant: {invariant}")

print("Exness project structure and safety invariants look valid.")
