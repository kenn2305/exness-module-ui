#import <UIKit/UIKit.h>

@class MUIRuntime;

NS_ASSUME_NONNULL_BEGIN

@interface MUIScreenEditorViewController : UIViewController
- (instancetype)initWithRuntime:(MUIRuntime *)runtime
                       rootView:(UIView *)rootView
                         tabBar:(nullable UITabBar *)tabBar
                       screenID:(NSString *)screenID;
@end

NS_ASSUME_NONNULL_END
