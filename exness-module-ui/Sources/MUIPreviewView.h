#import <UIKit/UIKit.h>

@class MUIModule;

NS_ASSUME_NONNULL_BEGIN

@interface MUIPreviewView : UIView
- (void)renderModules:(NSArray<MUIModule *> *)modules;
@end

NS_ASSUME_NONNULL_END
