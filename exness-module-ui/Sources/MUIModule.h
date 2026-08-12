#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MUIModule : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *controllerClass;
@property (nonatomic, copy) NSString *originalTitle;
@property (nonatomic, copy) NSString *displayTitle;
@property (nonatomic, strong, nullable) UIImage *originalImage;
@property (nonatomic, strong, nullable) UIImage *originalSelectedImage;
@property (nonatomic, copy, nullable) NSString *customIconPath;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) NSInteger originalIndex;
@property (nonatomic, weak, nullable) UIViewController *controller;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)moduleFromDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
