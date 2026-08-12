#import <UIKit/UIKit.h>

@class MUIScreenCandidate;

NS_ASSUME_NONNULL_BEGIN

@interface MUIScreenOverlayManager : NSObject
+ (instancetype)sharedManager;
- (NSString *)screenIDForViewController:(UIViewController *)viewController;
- (NSArray<MUIScreenCandidate *> *)scanCandidatesInRootView:(UIView *)rootView
                                                   tabBar:(nullable UITabBar *)tabBar;
- (void)removeOverlaysAndRestoreOriginals;
- (void)removeOverlayAndRestoreOriginalsForRootView:(UIView *)rootView;
- (void)applyScreenID:(NSString *)screenID
             rootView:(UIView *)rootView
               tabBar:(nullable UITabBar *)tabBar;
@end

NS_ASSUME_NONNULL_END
