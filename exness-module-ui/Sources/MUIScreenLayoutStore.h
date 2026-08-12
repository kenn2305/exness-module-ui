#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MUIScreenLayoutStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<NSDictionary *> *)elementsForScreenID:(NSString *)screenID;
- (BOOL)saveElements:(NSArray<NSDictionary *> *)elements
         forScreenID:(NSString *)screenID
               error:(NSError **)error;
- (BOOL)resetScreenID:(NSString *)screenID error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
