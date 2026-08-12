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
- (void)invalidateRootView:(UIView *)rootView;
- (void)sourceGeometryDidChange:(UIView *)sourceView;
- (void)sourceView:(UIView *)sourceView didSetHidden:(BOOL)hidden;
- (void)sourceView:(UIView *)sourceView didSetAlpha:(CGFloat)alpha;
- (void)sourceLifecycleDidChange:(UIView *)sourceView;
- (BOOL)sourceContentDidChange:(UIView *)sourceView;
- (void)applyScreenID:(NSString *)screenID
             rootView:(UIView *)rootView
               tabBar:(nullable UITabBar *)tabBar;
- (CGRect)resolvedRootFrameForElement:(NSDictionary *)element
                            candidate:(nullable MUIScreenCandidate *)candidate
                             rootView:(UIView *)rootView
                           candidates:(NSArray<MUIScreenCandidate *> *)candidates;
- (void)captureAttachmentForElement:(NSMutableDictionary *)element
                          rootFrame:(CGRect)rootFrame
                          candidate:(nullable MUIScreenCandidate *)candidate
                           rootView:(UIView *)rootView
                         candidates:(NSArray<MUIScreenCandidate *> *)candidates;
@end

NS_ASSUME_NONNULL_END
