#import "MUIScreenLayoutStore.h"
#import "MUIConfigStore.h"

static NSString * const MUIScreenLayoutFileName = @"screen-layout.json";
static NSString * const MUIScreenLayoutErrorDomain = @"com.vietanh.exnessmoduleui.screen-layout";

@interface MUIScreenLayoutStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *cache;
@end

@implementation MUIScreenLayoutStore

+ (instancetype)sharedStore {
    static MUIScreenLayoutStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [MUIScreenLayoutStore new]; });
    return store;
}

- (NSURL *)fileURL {
    return [[[MUIConfigStore sharedStore] baseDirectoryURL]
        URLByAppendingPathComponent:MUIScreenLayoutFileName];
}

- (NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *)loadCache {
    if (self.cache) return self.cache;
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
    if (!data) {
        self.cache = [NSMutableDictionary dictionary];
        return self.cache;
    }
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *screens = [root[@"screens"] isKindOfClass:NSDictionary.class] ? root[@"screens"] : @{};
    self.cache = [screens mutableCopy];
    return self.cache;
}

- (NSArray<NSDictionary *> *)elementsForScreenID:(NSString *)screenID {
    if (screenID.length == 0) return @[];
    NSArray *elements = [self loadCache][screenID];
    if (![elements isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *valid = [NSMutableArray array];
    for (id element in elements) {
        if ([element isKindOfClass:NSDictionary.class]) [valid addObject:[element mutableCopy]];
    }
    return valid;
}

- (BOOL)writeCache:(NSError **)error {
    NSURL *directory = [[MUIConfigStore sharedStore] baseDirectoryURL];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) return NO;
    NSDictionary *root = @{
        @"schema_version": @1,
        @"screens": self.cache ?: @{}
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:root
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!json) return NO;
    return [json writeToURL:self.fileURL options:NSDataWritingAtomic error:error];
}

- (BOOL)saveElements:(NSArray<NSDictionary *> *)elements
         forScreenID:(NSString *)screenID
               error:(NSError **)error {
    if (screenID.length == 0) {
        if (error) *error = [NSError errorWithDomain:MUIScreenLayoutErrorDomain code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing screen identifier."}];
        return NO;
    }
    NSMutableArray *sanitized = [NSMutableArray array];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (NSDictionary *element in elements) {
        NSString *identifier = element[@"id"];
        NSString *type = element[@"type"];
        NSDictionary *frame = element[@"frame"];
        if (![identifier isKindOfClass:NSString.class] || identifier.length == 0 ||
            [identifiers containsObject:identifier] ||
            ![type isKindOfClass:NSString.class] ||
            ![frame isKindOfClass:NSDictionary.class]) continue;
        CGFloat width = [frame[@"w"] doubleValue];
        CGFloat height = [frame[@"h"] doubleValue];
        if (width <= 0.0 || height <= 0.0 || width > 50.0 || height > 50.0) continue;
        [identifiers addObject:identifier];
        [sanitized addObject:[element copy]];
    }
    [self loadCache][screenID] = sanitized;
    return [self writeCache:error];
}

- (BOOL)resetScreenID:(NSString *)screenID error:(NSError **)error {
    if (screenID.length == 0) return YES;
    [[self loadCache] removeObjectForKey:screenID];
    return [self writeCache:error];
}

@end
