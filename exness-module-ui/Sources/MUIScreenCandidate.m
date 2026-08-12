#import "MUIScreenCandidate.h"

@implementation MUIScreenCandidate

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = @"";
        _displayName = @"Icon";
        _contentType = @"icon";
        _componentRole = @"Image";
        _containerIdentifier = @"";
        _scrollContainerIdentifier = @"";
        _frameInRoot = CGRectZero;
        _frameInContainer = CGRectZero;
        _scrollContainerFrameInRoot = CGRectZero;
        _textAlignment = NSTextAlignmentCenter;
        _lineBreakMode = NSLineBreakByTruncatingTail;
        _numberOfLines = 1;
        _renderedPrimitive = NO;
    }
    return self;
}

@end
