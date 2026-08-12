#import <UIKit/UIKit.h>
#import "Sources/MUIRuntime.h"

static BOOL MUIEventEndsInBottomNavigation(UIEvent *event, UIWindow *window) {
    if (event.type != UIEventTypeTouches || !window) return NO;
    CGFloat threshold = CGRectGetHeight(window.bounds) * 0.62;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded) continue;
        CGPoint point = [touch locationInView:window];
        if (point.y >= threshold) return YES;
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
    BOOL potentialTabChange = MUIEventEndsInBottomNavigation(event, self);
    if (potentialTabChange) {
        [[MUIRuntime sharedRuntime] prepareForPossibleScreenTransition];
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

- (void)didMoveToWindow {
    %orig;
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
