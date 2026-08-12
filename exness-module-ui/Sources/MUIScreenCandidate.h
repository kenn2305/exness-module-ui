#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MUIScreenCandidate : NSObject
@property (nonatomic, weak, nullable) UIView *sourceView;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, strong, nullable) UIColor *textColor;
@property (nonatomic, strong, nullable) UIFont *font;
@property (nonatomic, assign) NSTextAlignment textAlignment;
@property (nonatomic, assign) NSLineBreakMode lineBreakMode;
@property (nonatomic, assign) NSInteger numberOfLines;
@property (nonatomic, assign) CGRect frameInRoot;
@property (nonatomic, assign) CGRect frameInContainer;
@property (nonatomic, weak, nullable) UIView *containerView;
@property (nonatomic, copy) NSString *containerIdentifier;
@property (nonatomic, weak, nullable) UIScrollView *scrollContainerView;
@property (nonatomic, copy) NSString *scrollContainerIdentifier;
@property (nonatomic, assign) CGRect scrollContainerFrameInRoot;
@property (nonatomic, copy) NSString *componentRole;
@property (nonatomic, assign, getter=isScrollingContent) BOOL scrollingContent;
@property (nonatomic, assign, getter=isActionable) BOOL actionable;
/// SwiftUI renders most Exness fields into leaf drawing views instead of
/// UILabel/UIImageView instances. These leaves are still real, movable views,
/// but their text/image payload cannot be mutated through UIKit directly.
@property (nonatomic, assign, getter=isRenderedPrimitive) BOOL renderedPrimitive;
@end

NS_ASSUME_NONNULL_END
