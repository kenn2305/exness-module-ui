#import <UIKit/UIKit.h>
#import "Sources/MUIRuntime.h"
#import "Sources/MUIScreenOverlayManager.h"

static BOOL MUIEventEndsInBottomNavigation(UIEvent *event, UIWindow *window, CGPoint *pointOut) {
    if (event.type != UIEventTypeTouches || !window) return NO;
    CGFloat threshold = MAX(CGRectGetHeight(window.bounds) * 0.80,
                            CGRectGetHeight(window.bounds) - 120.0);
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded) continue;
        CGPoint point = [touch locationInView:window];
        if (point.y >= threshold) {
            if (pointOut) *pointOut = point;
            return YES;
        }
    }
    return NO;
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    [[MUIRuntime sharedRuntime] observeWindow:self];
}

- (void)becomeKeyWindow {
    %orig;
    [[MUIRuntime sharedRuntime] observeWindow:self];
}

- (void)setRootViewController:(UIViewController *)rootViewController {
    %orig;
    [[MUIRuntime sharedRuntime] observeWindow:self];
}

- (void)sendEvent:(UIEvent *)event {
    CGPoint tabPoint = CGPointZero;
    BOOL potentialTabChange = MUIEventEndsInBottomNavigation(event, self, &tabPoint);
    if (potentialTabChange) {
        [[MUIRuntime sharedRuntime] prepareForTabSelectionAtPoint:tabPoint inWindow:self];
    }
    %orig;
    if (potentialTabChange) {
        [[MUIRuntime sharedRuntime] completePossibleScreenTransition];
    }
}

%end

%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[MUIRuntime sharedRuntime] observeWindow:self.view.window];
    [[MUIRuntime sharedRuntime] observeTabBarController:self];
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    %orig;
    [[MUIRuntime sharedRuntime] observeTabBarController:self];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [[MUIRuntime sharedRuntime] prepareForPossibleScreenTransition];
    %orig;
    [[MUIRuntime sharedRuntime] completePossibleScreenTransition];
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    [[MUIRuntime sharedRuntime] prepareForPossibleScreenTransition];
    %orig;
    [[MUIRuntime sharedRuntime] completePossibleScreenTransition];
}

%end

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    [[MUIRuntime sharedRuntime] prepareContentViewController:self];
    %orig;
    [[MUIRuntime sharedRuntime] observeContentViewController:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[MUIRuntime sharedRuntime] observeContentViewController:self];
}

%end

%hook UIView

- (void)setFrame:(CGRect)frame {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceGeometryDidChange:self];
}

- (void)setCenter:(CGPoint)center {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceGeometryDidChange:self];
}

- (void)setBounds:(CGRect)bounds {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceGeometryDidChange:self];
}

- (void)setTransform:(CGAffineTransform)transform {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceGeometryDidChange:self];
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceView:self didSetHidden:hidden];
}

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceView:self didSetAlpha:alpha];
}

- (void)setNeedsDisplay {
    %orig;
    if ([[MUIScreenOverlayManager sharedManager] sourceContentDidChange:self]) {
        [[MUIRuntime sharedRuntime] viewHierarchyDidChange:self];
    }
}

- (void)setNeedsDisplayInRect:(CGRect)rect {
    %orig;
    if ([[MUIScreenOverlayManager sharedManager] sourceContentDidChange:self]) {
        [[MUIRuntime sharedRuntime] viewHierarchyDidChange:self];
    }
}

- (void)didMoveToSuperview {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceLifecycleDidChange:self];
}

- (void)didMoveToWindow {
    %orig;
    [[MUIScreenOverlayManager sharedManager] sourceLifecycleDidChange:self];
    [[MUIRuntime sharedRuntime] viewHierarchyDidChange:self];
}

%end

%ctor {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.exness.mobile"]) {
            return;
        }
        NSLog(@"[ExnessModuleUI] Loaded");
    }
}
