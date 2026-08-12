#import <UIKit/UIKit.h>
#import "MUIConfigStore.h"
#import "MUIConstants.h"
#import "MUIModule.h"

static NSString * const MUIConfigErrorDomain = @"com.vietanh.exnessmoduleui.config";

@implementation MUIConfigStore

+ (instancetype)sharedStore {
    static MUIConfigStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [MUIConfigStore new]; });
    return store;
}

- (NSURL *)baseDirectoryURL {
    NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    return [support URLByAppendingPathComponent:MUIConfigDirectoryName isDirectory:YES];
}

- (NSURL *)iconsDirectoryURL {
    return [self.baseDirectoryURL URLByAppendingPathComponent:@"icons" isDirectory:YES];
}

- (BOOL)ensureDirectories:(NSError **)error {
    return [[NSFileManager defaultManager] createDirectoryAtURL:self.iconsDirectoryURL
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:error];
}

- (NSURL *)configURL {
    return [self.baseDirectoryURL URLByAppendingPathComponent:MUIConfigFileName];
}

- (NSURL *)backupURL {
    return [self.baseDirectoryURL URLByAppendingPathComponent:MUIBackupFileName];
}

- (NSArray<MUIModule *> *)loadModulesWithError:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:self.configURL options:0 error:error];
    if (!data) return nil;

    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class] || [root[@"schema_version"] integerValue] != MUISchemaVersion) {
        if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Unsupported or invalid configuration schema."}];
        return nil;
    }
    if (![root[@"bundle_id"] isEqualToString:MUIBundleIdentifier]) {
        if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Configuration belongs to another application."}];
        return nil;
    }

    NSArray *rawModules = root[@"modules"];
    if (![rawModules isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<MUIModule *> *modules = [NSMutableArray array];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (NSDictionary *raw in rawModules) {
        MUIModule *module = [MUIModule moduleFromDictionary:raw];
        if (!module || [ids containsObject:module.identifier]) {
            if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"Configuration contains an invalid or duplicate module."}];
            return nil;
        }
        [ids addObject:module.identifier];
        [modules addObject:module];
    }
    return modules;
}

- (BOOL)saveModules:(NSArray<MUIModule *> *)modules error:(NSError **)error {
    if (![self ensureDirectories:error]) return NO;
    if (modules.count == 0) {
        if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:4
                                            userInfo:@{NSLocalizedDescriptionKey: @"At least one module is required."}];
        return NO;
    }

    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    NSMutableArray *rawModules = [NSMutableArray arrayWithCapacity:modules.count];
    NSInteger enabledCount = 0;
    for (MUIModule *module in modules) {
        if (module.identifier.length == 0 || [ids containsObject:module.identifier]) {
            if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:5
                                                userInfo:@{NSLocalizedDescriptionKey: @"Module identifiers must be unique."}];
            return NO;
        }
        [ids addObject:module.identifier];
        if (module.enabled) enabledCount++;
        [rawModules addObject:module.dictionaryRepresentation];
    }
    if (enabledCount == 0) {
        if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:6
                                            userInfo:@{NSLocalizedDescriptionKey: @"At least one module must remain visible."}];
        return NO;
    }

    NSDictionary *root = @{
        @"schema_version": @(MUISchemaVersion),
        @"bundle_id": MUIBundleIdentifier,
        @"revision": @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0)),
        @"modules": rawModules
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
    if (!json) return NO;

    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:self.configURL.path]) {
        [fm removeItemAtURL:self.backupURL error:nil];
        if (![fm copyItemAtURL:self.configURL toURL:self.backupURL error:error]) return NO;
    }

    NSURL *temporaryURL = [self.baseDirectoryURL URLByAppendingPathComponent:@"layout.json.tmp"];
    if (![json writeToURL:temporaryURL options:NSDataWritingAtomic error:error]) return NO;
    if ([fm fileExistsAtPath:self.configURL.path]) {
        NSURL *resultURL = nil;
        [fm replaceItemAtURL:self.configURL
               withItemAtURL:temporaryURL
              backupItemName:nil
                     options:0
            resultingItemURL:&resultURL
                       error:error];
        return resultURL != nil;
    }
    return [fm moveItemAtURL:temporaryURL toURL:self.configURL error:error];
}

- (BOOL)restoreBackupWithError:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:self.backupURL.path]) return YES;
    [fm removeItemAtURL:self.configURL error:nil];
    return [fm copyItemAtURL:self.backupURL toURL:self.configURL error:error];
}

- (BOOL)resetWithError:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL ok = YES;
    if ([fm fileExistsAtPath:self.configURL.path]) {
        ok = [fm removeItemAtURL:self.configURL error:error];
    }
    return ok;
}

- (NSString *)saveIconImage:(UIImage *)image forModuleID:(NSString *)moduleID error:(NSError **)error {
    if (![self ensureDirectories:error]) return nil;
    if (!image || moduleID.length == 0) return nil;

    CGSize size = CGSizeMake(90.0, 90.0);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = CGRectMake(0, 0, size.width, size.height);
        CGFloat scale = MIN(size.width / image.size.width, size.height / image.size.height);
        CGSize fitted = CGSizeMake(image.size.width * scale, image.size.height * scale);
        CGRect target = CGRectMake((size.width - fitted.width) / 2.0,
                                   (size.height - fitted.height) / 2.0,
                                   fitted.width, fitted.height);
        [image drawInRect:target];
        (void)bounds;
    }];
    NSData *png = UIImagePNGRepresentation(normalized);
    if (!png || png.length > 2 * 1024 * 1024) {
        if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:7
                                            userInfo:@{NSLocalizedDescriptionKey: @"The selected icon could not be normalized."}];
        return nil;
    }

    NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSString *safeID = [[moduleID componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    NSString *fileName = [NSString stringWithFormat:@"%@.png", safeID];
    NSURL *url = [self.iconsDirectoryURL URLByAppendingPathComponent:fileName];
    if (![png writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    return [@"icons" stringByAppendingPathComponent:fileName];
}

- (NSString *)saveOriginalImage:(UIImage *)image forElementID:(NSString *)elementID error:(NSError **)error {
    if (![self ensureDirectories:error]) return nil;
    if (!image || elementID.length == 0 || !image.CGImage) return nil;

    // Screen overlays may be enlarged far beyond tab-icon size. Preserve the
    // source pixels instead of passing through the 90x90 tab normalization.
    NSData *png = UIImagePNGRepresentation(image);
    if (!png || png.length > 80 * 1024 * 1024) {
        if (error) *error = [NSError errorWithDomain:MUIConfigErrorDomain code:8
                                            userInfo:@{NSLocalizedDescriptionKey: @"The original image is invalid or larger than 80 MB."}];
        return nil;
    }

    NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSString *safeID = [[elementID componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    NSString *fileName = [NSString stringWithFormat:@"%@_original.png", safeID];
    NSURL *url = [self.iconsDirectoryURL URLByAppendingPathComponent:fileName];
    if (![png writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    return [@"icons" stringByAppendingPathComponent:fileName];
}

- (UIImage *)imageAtRelativePath:(NSString *)relativePath {
    if (relativePath.length == 0 || [relativePath containsString:@".."] || [relativePath hasPrefix:@"/"]) return nil;
    NSURL *url = [self.baseDirectoryURL URLByAppendingPathComponent:relativePath];
    NSString *base = self.baseDirectoryURL.URLByStandardizingPath.path;
    NSString *candidate = url.URLByStandardizingPath.path;
    if (![candidate hasPrefix:base]) return nil;
    return [UIImage imageWithContentsOfFile:candidate];
}

@end
