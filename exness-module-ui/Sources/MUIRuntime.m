#import "MUIRuntime.h"
#import "MUIConfigStore.h"
#import "MUIConstants.h"
#import "MUIDesignerViewController.h"
#import "MUIScreenEditorViewController.h"
#import "MUIScreenOverlayManager.h"
#import "MUIModule.h"

@interface MUIRuntime ()
@property (nonatomic, weak, readwrite) UITabBarController *tabBarController;
@property (nonatomic, weak, readwrite) UIWindow *appWindow;
@property (nonatomic, copy, readwrite) NSArray<MUIModule *> *currentModules;
@property (nonatomic, copy) NSArray<MUIModule *> *baselineModules;
@property (nonatomic, copy) NSArray<UIViewController *> *baselineControllers;
@property (nonatomic, assign) BOOL applying;
@property (nonatomic, assign) BOOL disableSavedLayoutForThisLaunch;
@property (nonatomic, assign) BOOL handledCrashMarker;
@property (nonatomic, weak) UILongPressGestureRecognizer *designerGesture;
@property (nonatomic, weak) UIView *currentScreenRootView;
@property (nonatomic, copy) NSString *currentScreenID;
@property (nonatomic, assign) BOOL hierarchyRefreshQueued;
@property (nonatomic, assign) NSInteger activeTabSlot;
@end

@implementation MUIRuntime

+ (instancetype)sharedRuntime {
    static MUIRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ runtime = [MUIRuntime new]; });
    return runtime;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentModules = @[];
        _baselineModules = @[];
        _baselineControllers = @[];
        _activeTabSlot = NSNotFound;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _disableSavedLayoutForThisLaunch = [defaults boolForKey:@"ExnessModuleUIApplyWatchdog"];
        [defaults setBool:NO forKey:@"ExnessModuleUIApplyWatchdog"];
    }
    return self;
}

- (BOOL)isUsableApplicationWindow:(UIWindow *)window {
    if (!window || window.hidden || window.alpha <= 0.01 || !window.rootViewController) return NO;
    return window.windowLevel == UIWindowLevelNormal;
}

- (void)observeWindow:(UIWindow *)window {
    if (![self isUsableApplicationWindow:window]) return;
    self.appWindow = window;
    [self installDesignerGestureOnView:window];
    [self refreshCurrentScreenLayout];
}

- (void)observeTabBarController:(UITabBarController *)tabBarController {
    if (!tabBarController || self.applying) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self captureAndConfigureTabBarController:tabBarController];
    });
}

- (void)observeContentViewController:(UIViewController *)viewController {
    if ([NSStringFromClass(viewController.class) hasPrefix:@"MUI"]) return;
    if (viewController.view.window) [self observeWindow:viewController.view.window];
    // Apply before the next frame is committed so the original icon never
    // flashes at its default position during a tab transition.
    [self refreshCurrentScreenLayout];
    // A next-runloop pass catches controllers that finish adding subviews in
    // viewWillAppear without introducing a visible fixed delay.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshCurrentScreenLayout];
    });
}

- (UIViewController *)tabRootControllerForController:(UIViewController *)viewController {
    if (!viewController || !self.tabBarController) return nil;
    UIViewController *cursor = viewController;
    while (cursor.parentViewController && cursor.parentViewController != self.tabBarController) {
        cursor = cursor.parentViewController;
    }
    if (cursor.parentViewController == self.tabBarController ||
        [self.tabBarController.viewControllers containsObject:cursor]) return cursor;
    if ([self.tabBarController.viewControllers containsObject:viewController]) return viewController;
    return nil;
}

- (void)prepareContentViewController:(UIViewController *)viewController {
    if (!viewController) return;
    if ([NSStringFromClass(viewController.class) hasPrefix:@"MUI"]) return;
    if (viewController.view.window) [self observeWindow:viewController.view.window];
    if (!self.tabBarController || !self.tabBarController.view.window) {
        [self refreshCurrentScreenLayout];
        return;
    }
    UITabBarController *owner = viewController.tabBarController;
    BOOL isRootTab = [self.tabBarController.viewControllers containsObject:viewController];
    if (owner != self.tabBarController && !isRootTab) return;

    // Use the controller receiving viewWillAppear instead of selectedViewController.
    // During an animated tab transition UIKit may not update selectedViewController
    // until later, which previously caused the layout to appear ~0.5 s late.
    UIViewController *leaf = [self topViewControllerFrom:viewController];
    UIViewController *tabRoot = [self tabRootControllerForController:viewController];
    if (!tabRoot) return;
    NSString *screenID = [self screenIDForController:leaf rootView:tabRoot.view];
    [[MUIScreenOverlayManager sharedManager] applyScreenID:screenID
                                                 rootView:tabRoot.view
                                                   tabBar:nil];
}

- (void)refreshCurrentScreenLayout {
    UIWindow *window = self.appWindow;
    if (![self isUsableApplicationWindow:window]) return;
    UIViewController *rootController = window.rootViewController;
    UIViewController *presented = [self topViewControllerFrom:rootController];
    if ([NSStringFromClass(presented.class) hasPrefix:@"MUI"]) return;

    UIViewController *selected = self.tabBarController.selectedViewController;
    if (!selected || !selected.view.window) selected = rootController;
    UIViewController *leaf = [self topViewControllerFrom:selected];
    UIView *rootView = selected.view.window ? selected.view : rootController.view;
    if (!rootView || !rootView.window) return;
    NSString *screenID = [self screenIDForController:leaf rootView:rootView];

    // Keep each tab's overlays attached to that tab's own root. UIKit hides and
    // reveals the complete hierarchy atomically, so custom content transitions
    // in the same frame as the native controls instead of flashing or arriving
    // on the next run loop.
    if (self.currentScreenRootView == rootView &&
               self.currentScreenID.length > 0 &&
               ![self.currentScreenID isEqualToString:screenID]) {
        [[MUIScreenOverlayManager sharedManager] removeOverlayAndRestoreOriginalsForRootView:rootView];
    }
    self.currentScreenRootView = rootView;
    self.currentScreenID = screenID;
    [[MUIScreenOverlayManager sharedManager] applyScreenID:screenID
                                                 rootView:rootView
                                                   tabBar:nil];
}

- (NSString *)stableLabelForView:(UIView *)view {
    NSString *value = view.accessibilityIdentifier;
    if (value.length == 0) value = view.accessibilityLabel;
    if (value.length == 0 && [view isKindOfClass:UIButton.class]) {
        value = [(UIButton *)view titleForState:UIControlStateNormal];
    }
    if (value.length == 0 && [view isKindOfClass:UILabel.class]) {
        value = ((UILabel *)view).text;
    }
    if (value.length == 0) return nil;
    value = [value stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
                                       locale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]];
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:allowed.invertedSet];
    NSString *normalized = [[parts componentsJoinedByString:@"-"] lowercaseString];
    while ([normalized containsString:@"--"]) {
        normalized = [normalized stringByReplacingOccurrencesOfString:@"--" withString:@"-"];
    }
    return normalized.length > 64 ? [normalized substringToIndex:64] : normalized;
}

- (NSString *)selectedNavigationMarkerInView:(UIView *)view rootView:(UIView *)rootView {
    if (!view || view.hidden || view.alpha <= 0.01) return nil;
    CGRect frame = [view.superview convertRect:view.frame toView:rootView];
    BOOL nearBottom = CGRectGetMidY(frame) >= CGRectGetHeight(rootView.bounds) * 0.60;
    BOOL selected = (view.accessibilityTraits & UIAccessibilityTraitSelected) != 0;
    if ([view isKindOfClass:UIButton.class]) selected = selected || ((UIButton *)view).selected;
    if (nearBottom && selected) {
        NSString *label = [self stableLabelForView:view];
        if (label.length > 0) return label;
    }
    for (UIView *child in view.subviews) {
        NSString *marker = [self selectedNavigationMarkerInView:child rootView:rootView];
        if (marker.length > 0) return marker;
    }
    return nil;
}

- (NSString *)primaryScreenMarkerInView:(UIView *)view rootView:(UIView *)rootView {
    if (!view || view.hidden || view.alpha <= 0.01 || view.tag == 0x4D553149 ||
        [NSStringFromClass(view.class) hasPrefix:@"MUI"]) return nil;
    NSString *best = nil;
    CGFloat bestScore = 0.0;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        CGRect frame = [view.superview convertRect:view.frame toView:rootView];
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL inHeader = CGRectGetMinY(frame) >= 20.0 &&
            CGRectGetMaxY(frame) <= CGRectGetHeight(rootView.bounds) * 0.22;
        if (inHeader && text.length > 0 && text.length < 80) {
            best = [self stableLabelForView:view];
            bestScore = label.font.pointSize * MAX(CGRectGetWidth(frame), 1.0);
        }
    }
    for (UIView *child in view.subviews) {
        NSString *candidate = [self primaryScreenMarkerInView:child rootView:rootView];
        if (candidate.length == 0) continue;
        CGFloat score = 1.0;
        if ([child isKindOfClass:UILabel.class]) {
            score = ((UILabel *)child).font.pointSize * MAX(CGRectGetWidth(child.bounds), 1.0);
        }
        if (!best || score > bestScore) {
            best = candidate;
            bestScore = score;
        }
    }
    return best;
}

- (NSString *)screenIDForController:(UIViewController *)controller rootView:(UIView *)rootView {
    NSString *base = [[MUIScreenOverlayManager sharedManager] screenIDForViewController:controller];
    if (self.activeTabSlot != NSNotFound) {
        return [NSString stringWithFormat:@"%@|tab-slot:%ld", base, (long)self.activeTabSlot];
    }
    NSString *screen = [self primaryScreenMarkerInView:rootView rootView:rootView];
    NSDictionary<NSString *, NSNumber *> *knownTabs = @{
        @"tai-khoan": @0, @"giao-dich": @1, @"thong-tin-chuyen-sau": @2,
        @"hieu-suat": @3, @"ho-so": @4
    };
    for (NSString *name in knownTabs) {
        if ([screen containsString:name]) {
            self.activeTabSlot = [knownTabs[name] integerValue];
            return [NSString stringWithFormat:@"%@|tab-slot:%ld", base, (long)self.activeTabSlot];
        }
    }
    if (screen.length > 0) return [NSString stringWithFormat:@"%@|screen:%@", base, screen];
    NSString *marker = [self selectedNavigationMarkerInView:rootView rootView:rootView];
    return marker.length > 0 ? [NSString stringWithFormat:@"%@|tab:%@", base, marker] : base;
}

- (void)prepareForPossibleScreenTransition {
    // Restore before the state mutation in the same input transaction. No
    // intermediate frame is committed, while a shared SwiftUI root can no
    // longer carry a previous tab's edited leaves into the next tab.
    if (self.currentScreenRootView) {
        [[MUIScreenOverlayManager sharedManager] removeOverlayAndRestoreOriginalsForRootView:self.currentScreenRootView];
    }
}

- (void)prepareForTabSelectionAtPoint:(CGPoint)point inWindow:(UIWindow *)window {
    [self prepareForPossibleScreenTransition];
    CGFloat width = MAX(CGRectGetWidth(window.bounds), 1.0);
    NSInteger slot = (NSInteger)floor((point.x / width) * 5.0);
    self.activeTabSlot = MIN(MAX(slot, 0), 4);
}

- (void)completePossibleScreenTransition {
    [self refreshCurrentScreenLayout];
    [self queueHierarchyRefresh];
}

- (void)queueHierarchyRefresh {
    if (self.hierarchyRefreshQueued) return;
    self.hierarchyRefreshQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hierarchyRefreshQueued = NO;
        [self refreshCurrentScreenLayout];
    });
}

- (void)viewHierarchyDidChange:(UIView *)view {
    if (!view || !self.appWindow || view.window != self.appWindow) return;
    if ([NSStringFromClass(view.class) hasPrefix:@"MUI"] || view.tag == 0x4D553149) return;
    if (self.currentScreenRootView &&
        (view == self.currentScreenRootView || [view isDescendantOfView:self.currentScreenRootView])) {
        [[MUIScreenOverlayManager sharedManager] invalidateRootView:self.currentScreenRootView];
    }
    [self queueHierarchyRefresh];
}

- (NSString *)identifierForController:(UIViewController *)controller
                            occurrence:(NSInteger)occurrence {
    NSString *className = NSStringFromClass(controller.class) ?: @"UIViewController";
    NSString *title = controller.tabBarItem.title ?: controller.title ?: @"untitled";
    return [NSString stringWithFormat:@"%@|%@#%ld", className, title, (long)occurrence];
}

- (NSArray<MUIModule *> *)inventoryControllers:(NSArray<UIViewController *> *)controllers {
    NSMutableDictionary<NSString *, NSNumber *> *classCounts = [NSMutableDictionary dictionary];
    NSMutableArray<MUIModule *> *modules = [NSMutableArray arrayWithCapacity:controllers.count];
    [controllers enumerateObjectsUsingBlock:^(UIViewController *controller, NSUInteger index, BOOL *stop) {
        NSString *className = NSStringFromClass(controller.class) ?: @"UIViewController";
        NSInteger occurrence = [classCounts[className] integerValue];
        classCounts[className] = @(occurrence + 1);

        UITabBarItem *item = controller.tabBarItem;
        MUIModule *module = [MUIModule new];
        module.identifier = [self identifierForController:controller occurrence:occurrence];
        module.controllerClass = className;
        module.originalTitle = item.title ?: controller.title ?: [NSString stringWithFormat:@"Module %lu", (unsigned long)index + 1];
        module.displayTitle = module.originalTitle;
        module.originalImage = item.image;
        module.originalSelectedImage = item.selectedImage;
        module.enabled = YES;
        module.originalIndex = index;
        module.controller = controller;
        [modules addObject:module];
    }];
    return modules;
}

- (void)captureAndConfigureTabBarController:(UITabBarController *)tabBarController {
    if (self.applying) return;
    NSArray<UIViewController *> *controllers = tabBarController.viewControllers;
    if (controllers.count < 2 || !tabBarController.view.window) return;

    BOOL newController = self.tabBarController != tabBarController;
    if (newController && self.baselineControllers.count > 0 && controllers.count < self.baselineControllers.count) {
        return;
    }
    if (newController || self.baselineControllers.count == 0) {
        self.tabBarController = tabBarController;
        self.baselineControllers = [controllers copy];
        self.baselineModules = [self inventoryControllers:controllers];
    } else {
        // The host app can rebuild native tabs after account/session changes. Refresh retained
        // controller instances only when the app presents a complete fresh set.
        NSSet *known = [NSSet setWithArray:self.baselineControllers];
        BOOL containsFreshController = NO;
        for (UIViewController *controller in controllers) {
            if (![known containsObject:controller]) {
                containsFreshController = YES;
                break;
            }
        }
        if (containsFreshController && controllers.count >= self.baselineControllers.count) {
            self.baselineControllers = [controllers copy];
            self.baselineModules = [self inventoryControllers:controllers];
        }
    }

    [self installDesignerGestureOnView:self.appWindow ?: tabBarController.view.window];

    if (self.disableSavedLayoutForThisLaunch && !self.handledCrashMarker) {
        self.handledCrashMarker = YES;
        [[MUIConfigStore sharedStore] resetWithError:nil];
        NSLog(@"[ExnessModuleUI] Previous Apply did not finish; saved layout disabled for safe recovery.");
        [self restoreBaselineWithoutSaving];
        return;
    }

    NSError *error = nil;
    NSArray<MUIModule *> *saved = [[MUIConfigStore sharedStore] loadModulesWithError:&error];
    if (saved.count > 0) {
        [self armApplyWatchdog];
        if (![self applyModules:saved error:&error]) {
            NSLog(@"[ExnessModuleUI] Refused saved layout: %@", error.localizedDescription);
            [self restoreBaselineWithoutSaving];
        }
        [self disarmApplyWatchdogAfterDelay];
    } else {
        self.currentModules = [self editableModulesFromBaselineUsingConfig:nil];
    }
}

- (void)armApplyWatchdog {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"ExnessModuleUIApplyWatchdog"];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)disarmApplyWatchdogAfterDelay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"ExnessModuleUIApplyWatchdog"];
        [NSUserDefaults.standardUserDefaults synchronize];
    });
}

- (void)installDesignerGestureOnView:(UIView *)view {
    if (!view) return;
    if (self.designerGesture && self.designerGesture.view == view) return;

    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleDesignerGesture:)];
    gesture.minimumPressDuration = 0.8;
    gesture.numberOfTouchesRequired = 3;
    gesture.cancelsTouchesInView = NO;
    [view addGestureRecognizer:gesture];
    self.designerGesture = gesture;
}

- (void)handleDesignerGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self presentDesigner];
    }
}

- (NSArray<MUIModule *> *)editableModulesFromBaselineUsingConfig:(NSArray<MUIModule *> * _Nullable)config {
    NSMutableDictionary<NSString *, MUIModule *> *baselineByID = [NSMutableDictionary dictionary];
    for (MUIModule *module in self.baselineModules) {
        baselineByID[module.identifier] = module;
    }

    NSMutableArray<MUIModule *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (MUIModule *configured in config ?: @[]) {
        MUIModule *baseline = baselineByID[configured.identifier];
        if (!baseline) continue;
        MUIModule *merged = [baseline copy];
        merged.displayTitle = configured.displayTitle.length > 0 ? configured.displayTitle : baseline.originalTitle;
        merged.customIconPath = configured.customIconPath;
        merged.enabled = configured.enabled;
        [result addObject:merged];
        [used addObject:merged.identifier];
    }
    for (MUIModule *baseline in self.baselineModules) {
        if (![used containsObject:baseline.identifier]) {
            [result addObject:[baseline copy]];
        }
    }
    return result;
}

- (BOOL)applyModules:(NSArray<MUIModule *> *)configuredModules error:(NSError **)error {
    if (!self.tabBarController || self.baselineModules.count == 0) return NO;
    NSArray<MUIModule *> *modules = [self editableModulesFromBaselineUsingConfig:configuredModules];

    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    for (MUIModule *module in modules) {
        if (!module.enabled || !module.controller) continue;
        UIViewController *controller = module.controller;
        UITabBarItem *item = controller.tabBarItem;
        item.title = module.displayTitle.length > 0 ? module.displayTitle : module.originalTitle;
        if (module.customIconPath.length > 0) {
            UIImage *custom = [[MUIConfigStore sharedStore] imageAtRelativePath:module.customIconPath];
            if (custom) {
                UIImage *templated = [custom imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                item.image = templated;
                item.selectedImage = templated;
            } else {
                item.image = module.originalImage;
                item.selectedImage = module.originalSelectedImage;
            }
        } else {
            item.image = module.originalImage;
            item.selectedImage = module.originalSelectedImage;
        }
        [controllers addObject:controller];
    }
    if (controllers.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.vietanh.exnessmoduleui.runtime" code:10
                                      userInfo:@{NSLocalizedDescriptionKey: @"No visible module remains after validation."}];
        }
        return NO;
    }

    UIViewController *selected = self.tabBarController.selectedViewController;
    self.applying = YES;
    [self.tabBarController setViewControllers:controllers animated:NO];
    if (selected && [controllers containsObject:selected]) {
        self.tabBarController.selectedViewController = selected;
    } else {
        self.tabBarController.selectedIndex = 0;
    }
    self.applying = NO;
    self.currentModules = modules;
    return YES;
}

- (NSArray<MUIModule *> *)editableSnapshot {
    NSMutableArray *snapshot = [NSMutableArray arrayWithCapacity:self.currentModules.count];
    for (MUIModule *module in self.currentModules) [snapshot addObject:[module copy]];
    return snapshot;
}

- (BOOL)applyAndSaveModules:(NSArray<MUIModule *> *)modules error:(NSError **)error {
    if (![[MUIConfigStore sharedStore] saveModules:modules error:error]) return NO;
    [self armApplyWatchdog];
    if (![self applyModules:modules error:error]) {
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"ExnessModuleUIApplyWatchdog"];
        [[MUIConfigStore sharedStore] restoreBackupWithError:nil];
        [self restoreBaselineWithoutSaving];
        return NO;
    }
    [self disarmApplyWatchdogAfterDelay];
    return YES;
}

- (void)restoreBaselineWithoutSaving {
    if (!self.tabBarController || self.baselineControllers.count == 0) return;
    self.applying = YES;
    for (MUIModule *module in self.baselineModules) {
        UITabBarItem *item = module.controller.tabBarItem;
        item.title = module.originalTitle;
        item.image = module.originalImage;
        item.selectedImage = module.originalSelectedImage;
    }
    [self.tabBarController setViewControllers:self.baselineControllers animated:NO];
    self.tabBarController.selectedIndex = 0;
    self.applying = NO;
    self.currentModules = [self editableModulesFromBaselineUsingConfig:nil];
}

- (BOOL)resetToOriginalWithError:(NSError **)error {
    if (![[MUIConfigStore sharedStore] resetWithError:error]) return NO;
    [self restoreBaselineWithoutSaving];
    return YES;
}

- (UIViewController *)topViewControllerFrom:(UIViewController *)controller {
    if (controller.presentedViewController) return [self topViewControllerFrom:controller.presentedViewController];
    if ([controller isKindOfClass:UINavigationController.class]) {
        return [self topViewControllerFrom:((UINavigationController *)controller).visibleViewController];
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return [self topViewControllerFrom:((UITabBarController *)controller).selectedViewController];
    }
    return controller;
}

- (void)presentDesigner {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.tabBarController || self.baselineModules.count < 2) {
            [self presentScreenEditor];
            return;
        }
        if (self.tabBarController.presentedViewController) return;
        MUIDesignerViewController *designer = [[MUIDesignerViewController alloc] initWithRuntime:self];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:designer];
        navigation.modalPresentationStyle = UIModalPresentationFormSheet;
        UIViewController *presenter = [self topViewControllerFrom:self.tabBarController];
        [presenter presentViewController:navigation animated:YES completion:nil];
    });
}

- (void)presentScreenEditor {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = self.appWindow;
        if (![self isUsableApplicationWindow:window]) return;
        UIViewController *rootController = window.rootViewController;
        UIViewController *contextController = self.tabBarController.selectedViewController ?: rootController;
        if (!contextController.view.window) contextController = rootController;
        UIViewController *leaf = [self topViewControllerFrom:contextController];
        if (!leaf || [NSStringFromClass(leaf.class) hasPrefix:@"MUI"]) return;
        // Exness nests a UIKit tab controller inside one shared SwiftUI host.
        // The selected UIKit controller only contains the header; the actual
        // account/trade fields live in currentScreenRootView. Always edit the
        // same root used by the apply engine so every visible drawing leaf is
        // discoverable and saved under the same screen ID.
        UIView *rootView = nil;
        NSUInteger bestCandidateCount = 0;
        NSArray<UIView *> *possibleRoots = @[
            self.currentScreenRootView ?: UIView.new,
            contextController.view ?: UIView.new,
            rootController.view ?: UIView.new
        ];
        for (UIView *possibleRoot in possibleRoots) {
            if (!possibleRoot.window || possibleRoot.window != window) continue;
            NSUInteger count = [[MUIScreenOverlayManager sharedManager]
                scanCandidatesInRootView:possibleRoot tabBar:nil].count;
            if (!rootView || count > bestCandidateCount) {
                rootView = possibleRoot;
                bestCandidateCount = count;
            }
        }
        if (!rootView) rootView = contextController.view;
        NSString *screenID = (rootView == self.currentScreenRootView && self.currentScreenID.length > 0)
            ? self.currentScreenID : [self screenIDForController:leaf rootView:rootView];
        [[MUIScreenOverlayManager sharedManager] removeOverlayAndRestoreOriginalsForRootView:rootView];
        MUIScreenEditorViewController *editor = [[MUIScreenEditorViewController alloc]
            initWithRuntime:self
                   rootView:rootView
                     tabBar:nil
                   screenID:screenID];
        [leaf presentViewController:editor animated:YES completion:nil];
    });
}

@end
