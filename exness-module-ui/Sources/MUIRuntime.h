#import <UIKit/UIKit.h>

@class MUIModule;

NS_ASSUME_NONNULL_BEGIN

@interface MUIRuntime : NSObject

@property (nonatomic, weak, readonly, nullable) UITabBarController *tabBarController;
@property (nonatomic, weak, readonly, nullable) UIWindow *appWindow;
@property (nonatomic, copy, readonly) NSArray<MUIModule *> *currentModules;

+ (instancetype)sharedRuntime;
- (void)observeWindow:(UIWindow *)window;
- (void)observeTabBarController:(UITabBarController *)tabBarController;
- (void)observeContentViewController:(UIViewController *)viewController;
- (void)prepareContentViewController:(UIViewController *)viewController;
- (void)prepareForPossibleScreenTransition;
- (void)prepareForTabSelectionAtPoint:(CGPoint)point inWindow:(UIWindow *)window;
- (void)completePossibleScreenTransition;
- (void)viewHierarchyDidChange:(UIView *)view;
- (void)refreshCurrentScreenLayout;
- (NSArray<MUIModule *> *)editableSnapshot;
- (BOOL)applyAndSaveModules:(NSArray<MUIModule *> *)modules error:(NSError **)error;
- (BOOL)resetToOriginalWithError:(NSError **)error;
- (void)presentDesigner;
- (void)presentScreenEditor;

@end

NS_ASSUME_NONNULL_END
