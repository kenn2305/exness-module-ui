#import <Foundation/Foundation.h>

@class MUIModule;
@class UIImage;

NS_ASSUME_NONNULL_BEGIN

@interface MUIConfigStore : NSObject

@property (nonatomic, readonly) NSURL *baseDirectoryURL;
@property (nonatomic, readonly) NSURL *iconsDirectoryURL;

+ (instancetype)sharedStore;
- (nullable NSArray<MUIModule *> *)loadModulesWithError:(NSError **)error;
- (BOOL)saveModules:(NSArray<MUIModule *> *)modules error:(NSError **)error;
- (BOOL)restoreBackupWithError:(NSError **)error;
- (BOOL)resetWithError:(NSError **)error;
- (nullable NSString *)saveIconImage:(UIImage *)image forModuleID:(NSString *)moduleID error:(NSError **)error;
- (nullable NSString *)saveOriginalImage:(UIImage *)image forElementID:(NSString *)elementID error:(NSError **)error;
- (nullable UIImage *)imageAtRelativePath:(NSString *)relativePath;

@end

NS_ASSUME_NONNULL_END
