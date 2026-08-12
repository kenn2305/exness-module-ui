#import "MUIModule.h"

@implementation MUIModule

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = @"";
        _controllerClass = @"";
        _originalTitle = @"";
        _displayTitle = @"";
        _enabled = YES;
        _originalIndex = NSNotFound;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MUIModule *copy = [[[self class] allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.controllerClass = self.controllerClass;
    copy.originalTitle = self.originalTitle;
    copy.displayTitle = self.displayTitle;
    copy.originalImage = self.originalImage;
    copy.originalSelectedImage = self.originalSelectedImage;
    copy.customIconPath = self.customIconPath;
    copy.enabled = self.enabled;
    copy.originalIndex = self.originalIndex;
    copy.controller = self.controller;
    return copy;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *result = [@{
        @"id": self.identifier ?: @"",
        @"controller_class": self.controllerClass ?: @"",
        @"original_title": self.originalTitle ?: @"",
        @"title": self.displayTitle ?: @"",
        @"enabled": @(self.enabled),
        @"original_index": @(self.originalIndex)
    } mutableCopy];
    if (self.customIconPath.length > 0) {
        result[@"icon_path"] = self.customIconPath;
    }
    return result;
}

+ (instancetype)moduleFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = dictionary[@"id"];
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return nil;

    MUIModule *module = [MUIModule new];
    module.identifier = identifier;
    if ([dictionary[@"controller_class"] isKindOfClass:NSString.class]) {
        module.controllerClass = dictionary[@"controller_class"];
    }
    if ([dictionary[@"original_title"] isKindOfClass:NSString.class]) {
        module.originalTitle = dictionary[@"original_title"];
    }
    if ([dictionary[@"title"] isKindOfClass:NSString.class]) {
        module.displayTitle = dictionary[@"title"];
    }
    module.enabled = dictionary[@"enabled"] ? [dictionary[@"enabled"] boolValue] : YES;
    module.originalIndex = [dictionary[@"original_index"] integerValue];
    if ([dictionary[@"icon_path"] isKindOfClass:NSString.class]) {
        module.customIconPath = dictionary[@"icon_path"];
    }
    return module;
}

@end
