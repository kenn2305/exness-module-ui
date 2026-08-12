#import "MUIScreenOverlayManager.h"
#import "MUIConfigStore.h"
#import "MUIScreenCandidate.h"
#import "MUIScreenLayoutStore.h"

static NSInteger const MUIScreenOverlayHostTag = 0x4D553149;

@interface MUIPassthroughView : UIView
@end

@implementation MUIPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface MUIForwardingButton : UIButton
@property (nonatomic, weak) UIControl *forwardTarget;
@property (nonatomic, copy, nullable) dispatch_block_t tapHandler;
@end

@implementation MUIForwardingButton
- (CGRect)imageRectForContentRect:(CGRect)contentRect {
    return contentRect;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self addTarget:self action:@selector(forwardTap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)forwardTap {
    if (self.tapHandler) self.tapHandler();
    else [self.forwardTarget sendActionsForControlEvents:UIControlEventTouchUpInside];
}
@end

@interface MUIScreenOverlayManager ()
@property (nonatomic, strong) NSMapTable<UIView *, UIView *> *hostsByRoot;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableArray<UIView *> *> *scrollHostsByRoot;
@property (nonatomic, strong) NSMapTable<UIView *, NSMapTable<UIView *, NSNumber *> *> *hiddenStatesByRoot;
@property (nonatomic, strong) NSMapTable<UIView *, NSMapTable<UIView *, NSNumber *> *> *alphaStatesByRoot;
@property (nonatomic, strong) NSMapTable<UIView *, NSString *> *screenIDsByRoot;
@end

@implementation MUIScreenOverlayManager

+ (instancetype)sharedManager {
    static MUIScreenOverlayManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [MUIScreenOverlayManager new]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hostsByRoot = [NSMapTable weakToStrongObjectsMapTable];
        _scrollHostsByRoot = [NSMapTable weakToStrongObjectsMapTable];
        _hiddenStatesByRoot = [NSMapTable weakToStrongObjectsMapTable];
        _alphaStatesByRoot = [NSMapTable weakToStrongObjectsMapTable];
        _screenIDsByRoot = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (UIViewController *)leafController:(UIViewController *)controller {
    if ([controller isKindOfClass:UINavigationController.class]) {
        UIViewController *visible = ((UINavigationController *)controller).visibleViewController;
        return visible ? [self leafController:visible] : controller;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
        return selected ? [self leafController:selected] : controller;
    }
    return controller;
}

- (NSString *)screenIDForViewController:(UIViewController *)viewController {
    UIViewController *leaf = [self leafController:viewController];
    NSString *className = NSStringFromClass(leaf.class) ?: @"UIViewController";
    NSString *title = leaf.navigationItem.title ?: leaf.title ?: @"screen";
    return [NSString stringWithFormat:@"%@|%@", className, title];
}

- (UIImage *)candidateImageForView:(UIView *)view {
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        return [button imageForState:UIControlStateNormal] ?: button.imageView.image;
    }
    if ([view isKindOfClass:UIImageView.class]) return ((UIImageView *)view).image;
    return nil;
}

- (NSString *)candidateTextForView:(UIView *)view {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    return nil;
}

- (NSString *)stableTextIdentifierWithBase:(NSString *)base
                                      text:(NSString *)text
                                     frame:(CGRect)frame {
    NSInteger x = (NSInteger)llround(CGRectGetMinX(frame) * 2.0);
    NSInteger y = (NSInteger)llround(CGRectGetMinY(frame) * 2.0);
    NSInteger w = (NSInteger)llround(CGRectGetWidth(frame) * 2.0);
    NSInteger h = (NSInteger)llround(CGRectGetHeight(frame) * 2.0);
    NSUInteger textHash = text.hash;
    return [NSString stringWithFormat:@"%@|text:%lu|frame:%ld:%ld:%ld:%ld",
                                      base ?: @"text",
                                      (unsigned long)textHash,
                                      (long)x,
                                      (long)y,
                                      (long)w,
                                      (long)h];
}

- (NSString *)textIdentifierBaseFromIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return @"";
    NSRange textRange = [identifier rangeOfString:@"|text:"];
    if (textRange.location == NSNotFound) return identifier;
    return [identifier substringToIndex:textRange.location];
}

- (BOOL)viewIsInsideButton:(UIView *)view {
    UIView *ancestor = view.superview;
    while (ancestor) {
        if ([ancestor isKindOfClass:UIButton.class]) return YES;
        ancestor = ancestor.superview;
    }
    return NO;
}

- (void)scanView:(UIView *)view
             path:(NSString *)path
             root:(UIView *)root
           tabBar:(UITabBar *)tabBar
          results:(NSMutableArray<MUIScreenCandidate *> *)results {
    if (!view || view.tag == MUIScreenOverlayHostTag || view == tabBar || [view isDescendantOfView:tabBar]) return;
    if (view != root && (view.hidden || view.alpha < 0.05)) return;

    UIImage *image = [self candidateImageForView:view];
    NSString *text = [self candidateTextForView:view];
    BOOL duplicateImageView = [view isKindOfClass:UIImageView.class] && [self viewIsInsideButton:view];
    CGRect frame = view == root ? root.bounds : [view.superview convertRect:view.frame toView:root];
    CGFloat width = CGRectGetWidth(frame);
    CGFloat height = CGRectGetHeight(frame);
    BOOL sensibleSize = width >= 12.0 && height >= 12.0 && width <= 380.0 && height <= 380.0;
    if (image && sensibleSize && !duplicateImageView) {
        MUIScreenCandidate *candidate = [MUIScreenCandidate new];
        candidate.sourceView = view;
        NSString *semantic = view.accessibilityIdentifier.length > 0 ? view.accessibilityIdentifier : view.accessibilityLabel;
        candidate.identifier = semantic.length > 0
            ? [NSString stringWithFormat:@"%@|%@", NSStringFromClass(view.class), semantic]
            : path;
        candidate.displayName = semantic.length > 0 ? semantic : NSStringFromClass(view.class);
        candidate.contentType = @"icon";
        candidate.image = image;
        candidate.frameInRoot = frame;
        candidate.actionable = [view isKindOfClass:UIControl.class];
        [results addObject:candidate];
    }
    if (text.length > 0 && sensibleSize) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) {
            MUIScreenCandidate *candidate = [MUIScreenCandidate new];
            candidate.sourceView = view;
            NSString *semantic = view.accessibilityIdentifier.length > 0 ? view.accessibilityIdentifier : view.accessibilityLabel;
            NSString *baseIdentifier = semantic.length > 0
                ? [NSString stringWithFormat:@"%@|text|%@", NSStringFromClass(view.class), semantic]
                : [path stringByAppendingString:@"|text"];
            candidate.identifier = [self stableTextIdentifierWithBase:baseIdentifier
                                                                 text:trimmed
                                                                frame:frame];
            candidate.displayName = trimmed;
            candidate.contentType = @"text";
            candidate.text = trimmed;
            if ([view isKindOfClass:UILabel.class]) {
                UILabel *label = (UILabel *)view;
                candidate.textColor = label.textColor;
                candidate.font = label.font;
                candidate.textAlignment = label.textAlignment;
                candidate.lineBreakMode = label.lineBreakMode;
                candidate.numberOfLines = label.numberOfLines;
            } else if ([view isKindOfClass:UIButton.class]) {
                UIButton *button = (UIButton *)view;
                candidate.textColor = [button titleColorForState:UIControlStateNormal] ?: button.tintColor;
                candidate.font = button.titleLabel.font;
                candidate.textAlignment = button.titleLabel.textAlignment;
                candidate.lineBreakMode = button.titleLabel.lineBreakMode;
                candidate.numberOfLines = button.titleLabel.numberOfLines;
            }
            candidate.frameInRoot = frame;
            candidate.actionable = [view isKindOfClass:UIControl.class];
            [results addObject:candidate];
        }
    }

    NSArray<UIView *> *subviews = view.subviews;
    [subviews enumerateObjectsUsingBlock:^(UIView *subview, NSUInteger index, BOOL *stop) {
        NSString *childPath = [path stringByAppendingFormat:@"/%@:%lu", NSStringFromClass(subview.class), (unsigned long)index];
        [self scanView:subview path:childPath root:root tabBar:tabBar results:results];
    }];
}

- (NSArray<MUIScreenCandidate *> *)scanCandidatesInRootView:(UIView *)rootView tabBar:(UITabBar *)tabBar {
    if (!rootView) return @[];
    NSMutableArray *results = [NSMutableArray array];
    [self scanView:rootView path:NSStringFromClass(rootView.class) root:rootView tabBar:tabBar results:results];
    return results;
}

- (NSMapTable<UIView *, NSNumber *> *)hiddenStatesForRoot:(UIView *)root create:(BOOL)create {
    NSMapTable *states = [self.hiddenStatesByRoot objectForKey:root];
    if (!states && create) {
        states = [NSMapTable weakToStrongObjectsMapTable];
        [self.hiddenStatesByRoot setObject:states forKey:root];
    }
    return states;
}

- (NSMapTable<UIView *, NSNumber *> *)alphaStatesForRoot:(UIView *)root create:(BOOL)create {
    NSMapTable *states = [self.alphaStatesByRoot objectForKey:root];
    if (!states && create) {
        states = [NSMapTable weakToStrongObjectsMapTable];
        [self.alphaStatesByRoot setObject:states forKey:root];
    }
    return states;
}

- (void)hideOriginalView:(UIView *)view inRoot:(UIView *)root {
    if (!view || !root) return;
    NSMapTable *states = [self hiddenStatesForRoot:root create:YES];
    if ([states objectForKey:view]) return;
    [states setObject:@(view.hidden) forKey:view];
    view.hidden = YES;
}

- (void)concealOriginalTextView:(UIView *)view inRoot:(UIView *)root {
    if (!view || !root) return;
    NSMapTable *states = [self alphaStatesForRoot:root create:YES];
    if (![states objectForKey:view]) [states setObject:@(view.alpha) forKey:view];
    view.alpha = 0.0;
}

- (void)removeOverlayAndRestoreOriginalsForRootView:(UIView *)rootView {
    if (!rootView) return;
    [[self.hostsByRoot objectForKey:rootView] removeFromSuperview];
    for (UIView *host in [self.scrollHostsByRoot objectForKey:rootView]) {
        [host removeFromSuperview];
    }
    NSMapTable *states = [self hiddenStatesForRoot:rootView create:NO];
    for (UIView *view in states.keyEnumerator) {
        NSNumber *hidden = [states objectForKey:view];
        view.hidden = hidden.boolValue;
    }
    [states removeAllObjects];
    NSMapTable *alphaStates = [self alphaStatesForRoot:rootView create:NO];
    for (UIView *view in alphaStates.keyEnumerator) {
        NSNumber *alpha = [alphaStates objectForKey:view];
        view.alpha = alpha.doubleValue;
    }
    [alphaStates removeAllObjects];
    [self.hostsByRoot removeObjectForKey:rootView];
    [self.scrollHostsByRoot removeObjectForKey:rootView];
    [self.hiddenStatesByRoot removeObjectForKey:rootView];
    [self.alphaStatesByRoot removeObjectForKey:rootView];
    [self.screenIDsByRoot removeObjectForKey:rootView];
}

- (void)removeOverlaysAndRestoreOriginals {
    NSMutableArray<UIView *> *roots = [NSMutableArray array];
    for (UIView *root in self.hostsByRoot.keyEnumerator) if (root) [roots addObject:root];
    for (UIView *root in self.hiddenStatesByRoot.keyEnumerator) {
        if (root && ![roots containsObject:root]) [roots addObject:root];
    }
    for (UIView *root in self.alphaStatesByRoot.keyEnumerator) {
        if (root && ![roots containsObject:root]) [roots addObject:root];
    }
    for (UIView *root in self.scrollHostsByRoot.keyEnumerator) {
        if (root && ![roots containsObject:root]) [roots addObject:root];
    }
    for (UIView *root in roots) [self removeOverlayAndRestoreOriginalsForRootView:root];
}

- (CGRect)frameFromDictionary:(NSDictionary *)dictionary inBounds:(CGRect)bounds {
    CGFloat x = [dictionary[@"x"] doubleValue] * CGRectGetWidth(bounds);
    CGFloat y = [dictionary[@"y"] doubleValue] * CGRectGetHeight(bounds);
    CGFloat width = [dictionary[@"w"] doubleValue] * CGRectGetWidth(bounds);
    CGFloat height = [dictionary[@"h"] doubleValue] * CGRectGetHeight(bounds);
    return CGRectMake(x, y, width, height);
}

- (UIImage *)imageForElement:(NSDictionary *)element fallback:(UIImage *)fallback {
    NSString *path = [element[@"icon_path"] isKindOfClass:NSString.class] ? element[@"icon_path"] : nil;
    UIImage *custom = path.length > 0 ? [[MUIConfigStore sharedStore] imageAtRelativePath:path] : nil;
    NSString *symbol = [element[@"symbol"] isKindOfClass:NSString.class] ? element[@"symbol"] : nil;
    UIImage *symbolImage = symbol.length > 0 ? [UIImage systemImageNamed:symbol] : nil;
    return custom ?: symbolImage ?: fallback;
}

- (NSString *)textForElement:(NSDictionary *)element {
    NSString *text = [element[@"text"] isKindOfClass:NSString.class] ? element[@"text"] : nil;
    return text.length > 0 ? text : @"Text";
}

- (void)styleTextLabel:(UILabel *)label inFrame:(CGRect)frame {
    CGFloat fontSize = MIN(MAX(CGRectGetHeight(frame) * 0.62, 8.0), 420.0);
    label.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.25;
    label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    label.shadowOffset = CGSizeMake(0.0, 1.0);
}

- (UIControlContentHorizontalAlignment)contentHorizontalAlignmentForTextAlignment:(NSTextAlignment)alignment {
    switch (alignment) {
        case NSTextAlignmentLeft:
        case NSTextAlignmentNatural:
            return UIControlContentHorizontalAlignmentLeft;
        case NSTextAlignmentRight:
            return UIControlContentHorizontalAlignmentRight;
        case NSTextAlignmentJustified:
        case NSTextAlignmentCenter:
        default:
            return UIControlContentHorizontalAlignmentCenter;
    }
}

- (void)applyTextStyleFromTarget:(MUIScreenCandidate *)target toLabel:(UILabel *)label inFrame:(CGRect)frame {
    if (!label) return;
    [self styleTextLabel:label inFrame:frame];
    if (target.textColor) label.textColor = target.textColor;
    label.textAlignment = target ? target.textAlignment : NSTextAlignmentCenter;
    label.lineBreakMode = target ? target.lineBreakMode : NSLineBreakByTruncatingTail;
    label.numberOfLines = target ? target.numberOfLines : 0;
    if (target.font) {
        CGFloat multiplier = CGRectGetHeight(frame) / MAX(CGRectGetHeight(target.frameInRoot), 1.0);
        label.font = [target.font fontWithSize:MIN(MAX(target.font.pointSize * multiplier, 8.0), 420.0)];
    }
}

- (UIControl *)nearestControlForView:(UIView *)view {
    UIView *cursor = view;
    while (cursor) {
        if ([cursor isKindOfClass:UIControl.class]) return (UIControl *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

- (UITableViewCell *)nearestTableCellForView:(UIView *)view {
    UIView *cursor = view;
    while (cursor) {
        if ([cursor isKindOfClass:UITableViewCell.class]) return (UITableViewCell *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

- (UITableView *)nearestTableViewForView:(UIView *)view {
    UIView *cursor = view;
    while (cursor) {
        if ([cursor isKindOfClass:UITableView.class]) return (UITableView *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

- (UICollectionViewCell *)nearestCollectionCellForView:(UIView *)view {
    UIView *cursor = view;
    while (cursor) {
        if ([cursor isKindOfClass:UICollectionViewCell.class]) return (UICollectionViewCell *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

- (UICollectionView *)nearestCollectionViewForView:(UIView *)view {
    UIView *cursor = view;
    while (cursor) {
        if ([cursor isKindOfClass:UICollectionView.class]) return (UICollectionView *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

- (BOOL)triggerOriginalActionForSourceView:(UIView *)sourceView {
    UIControl *control = [self nearestControlForView:sourceView];
    if (control) {
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }

    UITableViewCell *tableCell = [self nearestTableCellForView:sourceView];
    UITableView *tableView = tableCell ? [self nearestTableViewForView:tableCell] : nil;
    NSIndexPath *tableIndexPath = tableCell ? [tableView indexPathForCell:tableCell] : nil;
    if (tableView && tableIndexPath) {
        [tableView selectRowAtIndexPath:tableIndexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        id<UITableViewDelegate> delegate = tableView.delegate;
        if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
            [delegate tableView:tableView didSelectRowAtIndexPath:tableIndexPath];
            return YES;
        }
    }

    UICollectionViewCell *collectionCell = [self nearestCollectionCellForView:sourceView];
    UICollectionView *collectionView = collectionCell ? [self nearestCollectionViewForView:collectionCell] : nil;
    NSIndexPath *collectionIndexPath = collectionCell ? [collectionView indexPathForCell:collectionCell] : nil;
    if (collectionView && collectionIndexPath) {
        [collectionView selectItemAtIndexPath:collectionIndexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
        id<UICollectionViewDelegate> delegate = collectionView.delegate;
        if ([delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
            [delegate collectionView:collectionView didSelectItemAtIndexPath:collectionIndexPath];
            return YES;
        }
    }

    return NO;
}

- (BOOL)canTriggerOriginalActionForSourceView:(UIView *)sourceView {
    if ([self nearestControlForView:sourceView]) return YES;

    UITableViewCell *tableCell = [self nearestTableCellForView:sourceView];
    UITableView *tableView = tableCell ? [self nearestTableViewForView:tableCell] : nil;
    NSIndexPath *tableIndexPath = tableCell ? [tableView indexPathForCell:tableCell] : nil;
    if (tableView && tableIndexPath &&
        [tableView.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return YES;

    UICollectionViewCell *collectionCell = [self nearestCollectionCellForView:sourceView];
    UICollectionView *collectionView = collectionCell ? [self nearestCollectionViewForView:collectionCell] : nil;
    NSIndexPath *collectionIndexPath = collectionCell ? [collectionView indexPathForCell:collectionCell] : nil;
    if (collectionView && collectionIndexPath &&
        [collectionView.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) return YES;

    return NO;
}

- (UIScrollView *)nearestScrollViewForView:(UIView *)view {
    UIView *cursor = view.superview;
    while (cursor) {
        if ([cursor isKindOfClass:UIScrollView.class]) return (UIScrollView *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

- (void)findScrollViewsInView:(UIView *)view
                         root:(UIView *)root
                         point:(CGPoint)point
                       results:(NSMutableArray<UIScrollView *> *)results {
    if (!view || view.tag == MUIScreenOverlayHostTag || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UIScrollView.class]) {
        CGPoint localPoint = [root convertPoint:point toView:view];
        if (CGRectContainsPoint(view.bounds, localPoint)) [results addObject:(UIScrollView *)view];
    }
    for (UIView *subview in view.subviews) {
        [self findScrollViewsInView:subview root:root point:point results:results];
    }
}

- (UIScrollView *)scrollViewAtRootPoint:(CGPoint)point rootView:(UIView *)rootView {
    NSMutableArray<UIScrollView *> *scrollViews = [NSMutableArray array];
    [self findScrollViewsInView:rootView root:rootView point:point results:scrollViews];
    return scrollViews.lastObject;
}

- (BOOL)scrollViewHasScrollableContent:(UIScrollView *)scrollView {
    if (!scrollView) return NO;
    CGSize contentSize = scrollView.contentSize;
    CGSize boundsSize = scrollView.bounds.size;
    return contentSize.height > boundsSize.height + 1.0 ||
           contentSize.width > boundsSize.width + 1.0;
}

- (UIView *)scrollHostForRoot:(UIView *)rootView scrollView:(UIScrollView *)scrollView {
    if (!rootView || !scrollView) return nil;
    NSMutableArray<UIView *> *hosts = [self.scrollHostsByRoot objectForKey:rootView];
    if (!hosts) {
        hosts = [NSMutableArray array];
        [self.scrollHostsByRoot setObject:hosts forKey:rootView];
    }
    for (UIView *host in hosts) {
        if (host.superview == scrollView) return host;
    }
    CGSize contentSize = scrollView.contentSize;
    contentSize.width = MAX(contentSize.width, CGRectGetWidth(scrollView.bounds));
    contentSize.height = MAX(contentSize.height, CGRectGetHeight(scrollView.bounds));
    MUIPassthroughView *host = [[MUIPassthroughView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentSize.width, contentSize.height)];
    host.backgroundColor = UIColor.clearColor;
    host.tag = MUIScreenOverlayHostTag;
    host.userInteractionEnabled = YES;
    [scrollView addSubview:host];
    [hosts addObject:host];
    return host;
}

- (CGRect)contentFrameForRootFrame:(CGRect)frame
                        scrollView:(UIScrollView *)scrollView
                          rootView:(UIView *)rootView {
    CGRect visibleFrame = [rootView convertRect:frame toView:scrollView];
    return CGRectOffset(visibleFrame, scrollView.contentOffset.x, scrollView.contentOffset.y);
}

- (CGRect)contentFrameForExistingTextTarget:(MUIScreenCandidate *)target
                                  rootFrame:(CGRect)frame
                                 scrollView:(UIScrollView *)scrollView
                                   rootView:(UIView *)rootView {
    if (!target.sourceView) return [self contentFrameForRootFrame:frame scrollView:scrollView rootView:rootView];
    CGRect sourceVisibleFrame = [target.sourceView.superview convertRect:target.sourceView.frame toView:rootView];
    CGRect sourceContentFrame = [self contentFrameForRootFrame:sourceVisibleFrame scrollView:scrollView rootView:rootView];
    CGFloat dx = CGRectGetMinX(frame) - CGRectGetMinX(target.frameInRoot);
    CGFloat dy = CGRectGetMinY(frame) - CGRectGetMinY(target.frameInRoot);
    return CGRectMake(CGRectGetMinX(sourceContentFrame) + dx,
                      CGRectGetMinY(sourceContentFrame) + dy,
                      CGRectGetWidth(frame),
                      CGRectGetHeight(frame));
}

- (void)trackManagedOverlay:(UIView *)overlay forRoot:(UIView *)rootView {
    if (!overlay || !rootView) return;
    NSMutableArray<UIView *> *hosts = [self.scrollHostsByRoot objectForKey:rootView];
    if (!hosts) {
        hosts = [NSMutableArray array];
        [self.scrollHostsByRoot setObject:hosts forKey:rootView];
    }
    if (![hosts containsObject:overlay]) [hosts addObject:overlay];
}

- (CGRect)parentFrameForExistingTextTarget:(MUIScreenCandidate *)target
                                 rootFrame:(CGRect)frame {
    UIView *sourceView = target.sourceView;
    UIView *parent = sourceView.superview;
    if (!sourceView || !parent) return frame;
    CGFloat dx = CGRectGetMinX(frame) - CGRectGetMinX(target.frameInRoot);
    CGFloat dy = CGRectGetMinY(frame) - CGRectGetMinY(target.frameInRoot);
    return CGRectMake(CGRectGetMinX(sourceView.frame) + dx,
                      CGRectGetMinY(sourceView.frame) + dy,
                      CGRectGetWidth(frame),
                      CGRectGetHeight(frame));
}

- (UIViewController *)topViewControllerFrom:(UIViewController *)controller {
    if (controller.presentedViewController) return [self topViewControllerFrom:controller.presentedViewController];
    if ([controller isKindOfClass:UINavigationController.class]) {
        return [self topViewControllerFrom:((UINavigationController *)controller).visibleViewController];
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return [self topViewControllerFrom:((UITabBarController *)controller).selectedViewController];
    }
    return controller;
}

- (void)presentActionPanelForElement:(NSDictionary *)element
                       forwardTarget:(UIControl *)forwardTarget
                          sourceView:(UIView *)sourceView {
    UIWindow *window = sourceView.window;
    UIViewController *presenter = window.rootViewController
        ? [self topViewControllerFrom:window.rootViewController] : nil;
    if (!presenter || presenter.presentedViewController) return;

    NSString *title = [element[@"panel_title"] isKindOfClass:NSString.class]
        ? element[@"panel_title"] : @"Số dư";
    NSString *message = [element[@"panel_message"] isKindOfClass:NSString.class]
        ? element[@"panel_message"] : @"Nhanh chóng di chuyển đến trang nạp/rút tiền trên trang web của broker";
    UIAlertController *panel = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [panel addAction:[UIAlertAction actionWithTitle:@"Tiền nạp" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [forwardTarget sendActionsForControlEvents:UIControlEventTouchUpInside];
    }]];
    [panel addAction:[UIAlertAction actionWithTitle:@"Tiền rút" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [forwardTarget sendActionsForControlEvents:UIControlEventTouchUpInside];
    }]];
    [panel addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    panel.popoverPresentationController.sourceView = sourceView;
    panel.popoverPresentationController.sourceRect = sourceView.bounds;
    [presenter presentViewController:panel animated:YES completion:nil];
}

- (void)applyScreenID:(NSString *)screenID rootView:(UIView *)rootView tabBar:(UITabBar *)tabBar {
    if (screenID.length == 0 || !rootView) return;
    NSArray<NSDictionary *> *elements = [[MUIScreenLayoutStore sharedStore] elementsForScreenID:screenID];
    BOOL hasTextElements = NO;
    for (NSDictionary *element in elements) {
        NSString *type = element[@"type"];
        if ([type isEqualToString:@"text"] || [element[@"content_type"] isEqualToString:@"text"]) {
            hasTextElements = YES;
            break;
        }
    }
    UIView *cachedHost = [self.hostsByRoot objectForKey:rootView];
    NSString *cachedScreenID = [self.screenIDsByRoot objectForKey:rootView];
    if (cachedHost && [cachedScreenID isEqualToString:screenID] && !hasTextElements) {
        [rootView bringSubviewToFront:cachedHost];
        for (UIView *scrollHost in [self.scrollHostsByRoot objectForKey:rootView]) {
            if (scrollHost.superview) [scrollHost.superview bringSubviewToFront:scrollHost];
        }
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [rootView layoutIfNeeded];
    [self removeOverlayAndRestoreOriginalsForRootView:rootView];
    if (elements.count == 0) {
        [CATransaction commit];
        return;
    }

    NSArray<MUIScreenCandidate *> *candidates = [self scanCandidatesInRootView:rootView tabBar:tabBar];
    NSMutableDictionary<NSString *, MUIScreenCandidate *> *candidateByID = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, MUIScreenCandidate *> *textCandidateByBaseID = [NSMutableDictionary dictionary];
    for (MUIScreenCandidate *candidate in candidates) {
        candidateByID[candidate.identifier] = candidate;
        if ([candidate.contentType isEqualToString:@"text"]) {
            NSString *base = [self textIdentifierBaseFromIdentifier:candidate.identifier];
            if (base.length > 0 && !textCandidateByBaseID[base]) textCandidateByBaseID[base] = candidate;
        }
    }

    MUIPassthroughView *host = [[MUIPassthroughView alloc] initWithFrame:rootView.bounds];
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    host.backgroundColor = UIColor.clearColor;
    host.tag = MUIScreenOverlayHostTag;
    [rootView addSubview:host];
    [self.hostsByRoot setObject:host forKey:rootView];
    [self.screenIDsByRoot setObject:screenID forKey:rootView];

    for (NSDictionary *element in elements) {
        NSString *type = element[@"type"];
        NSString *targetID = element[@"target_id"];
        MUIScreenCandidate *target = [type isEqualToString:@"existing"] ? candidateByID[targetID] : nil;
        BOOL elementIsText = [type isEqualToString:@"text"] || [element[@"content_type"] isEqualToString:@"text"];
        if (!target && elementIsText && [targetID isKindOfClass:NSString.class]) {
            target = textCandidateByBaseID[[self textIdentifierBaseFromIdentifier:targetID]];
        }
        if ([element[@"hidden"] boolValue]) {
            if (target.sourceView) {
                if (elementIsText || [target.contentType isEqualToString:@"text"]) {
                    [self concealOriginalTextView:target.sourceView inRoot:rootView];
                } else {
                    [self hideOriginalView:target.sourceView inRoot:rootView];
                }
            }
            continue;
        }

        CGRect frame = [self frameFromDictionary:element[@"frame"] inBounds:rootView.bounds];
        if (CGRectGetWidth(frame) < 4.0 || CGRectGetHeight(frame) < 4.0) continue;
        BOOL isTextElement = elementIsText ||
            [target.contentType isEqualToString:@"text"];
        if (isTextElement) {
            NSString *text = [element[@"text"] isKindOfClass:NSString.class] ? element[@"text"] : target.text;
            NSString *displayText = text.length > 0 ? text : [self textForElement:element];
            BOOL hasOriginalAction = target.sourceView && [self canTriggerOriginalActionForSourceView:target.sourceView];
            UIView *textParent = host;
            CGRect textFrame = frame;
            BOOL parentAnchoredText = target.sourceView.superview != nil;
            if (parentAnchoredText) {
                textParent = target.sourceView.superview;
                textFrame = [self parentFrameForExistingTextTarget:target rootFrame:frame];
            } else if (!hasOriginalAction) {
                UIScrollView *scrollView = target.sourceView
                    ? [self nearestScrollViewForView:target.sourceView]
                    : [self scrollViewAtRootPoint:CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame))
                                         rootView:rootView];
                if ([self scrollViewHasScrollableContent:scrollView]) {
                    UIView *scrollHost = [self scrollHostForRoot:rootView scrollView:scrollView];
                    if (scrollHost) {
                        textParent = scrollHost;
                        textFrame = target.sourceView
                            ? [self contentFrameForExistingTextTarget:target
                                                            rootFrame:frame
                                                           scrollView:scrollView
                                                             rootView:rootView]
                            : [self contentFrameForRootFrame:frame
                                                  scrollView:scrollView
                                                    rootView:rootView];
                    }
                }
            }
            UIView *textOverlay = nil;
            if (hasOriginalAction) {
                MUIForwardingButton *button = [[MUIForwardingButton alloc] initWithFrame:textFrame];
                [button setTitle:displayText forState:UIControlStateNormal];
                [button setTitleColor:target.textColor ?: UIColor.whiteColor forState:UIControlStateNormal];
                button.titleLabel.numberOfLines = target.numberOfLines;
                button.titleLabel.textAlignment = target.textAlignment;
                button.titleLabel.lineBreakMode = target.lineBreakMode;
                button.titleLabel.adjustsFontSizeToFitWidth = YES;
                button.titleLabel.minimumScaleFactor = 0.25;
                button.contentHorizontalAlignment = [self contentHorizontalAlignmentForTextAlignment:target.textAlignment];
                button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
                CGFloat fontSize = MIN(MAX(CGRectGetHeight(textFrame) * 0.62, 8.0), 420.0);
                if (target.font) {
                    CGFloat multiplier = CGRectGetHeight(textFrame) / MAX(CGRectGetHeight(target.frameInRoot), 1.0);
                    fontSize = MIN(MAX(target.font.pointSize * multiplier, 8.0), 420.0);
                    button.titleLabel.font = [target.font fontWithSize:fontSize];
                } else {
                    button.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
                }
                button.backgroundColor = UIColor.clearColor;
                button.accessibilityLabel = element[@"name"] ?: target.displayName;
                __weak typeof(self) weakSelf = self;
                __weak UIView *weakSource = target.sourceView;
                button.tapHandler = ^{
                    [weakSelf triggerOriginalActionForSourceView:weakSource];
                };
                textOverlay = button;
            } else {
                UILabel *label = [[UILabel alloc] initWithFrame:textFrame];
                label.text = displayText;
                label.backgroundColor = UIColor.clearColor;
                label.userInteractionEnabled = NO;
                [self applyTextStyleFromTarget:target toLabel:label inFrame:textFrame];
                textOverlay = label;
            }
            [textParent addSubview:textOverlay];
            if (textParent != host) [self trackManagedOverlay:textOverlay forRoot:rootView];
            if (target.sourceView) [self concealOriginalTextView:target.sourceView inRoot:rootView];
            continue;
        }
        UIImage *image = [self imageForElement:element fallback:target.image];
        if (!image) continue;

        NSString *actionTargetID = element[@"action_target"];
        MUIScreenCandidate *actionCandidate = candidateByID[actionTargetID ?: targetID];
        UIControl *actionControl = [actionCandidate.sourceView isKindOfClass:UIControl.class]
            ? (UIControl *)actionCandidate.sourceView : nil;

        UIView *overlay = nil;
        BOOL isCustom = [type isEqualToString:@"custom"];
        if (actionControl || isCustom) {
            MUIForwardingButton *button = [[MUIForwardingButton alloc] initWithFrame:frame];
            [button setImage:image forState:UIControlStateNormal];
            button.imageView.contentMode = UIViewContentModeScaleAspectFit;
            button.tintColor = target.sourceView.tintColor ?: rootView.tintColor;
            button.forwardTarget = actionControl;
            button.accessibilityLabel = element[@"name"] ?: target.displayName;
            if (isCustom) {
                __weak typeof(self) weakSelf = self;
                __weak UIControl *weakTarget = actionControl;
                __weak UIView *weakSource = button;
                button.tapHandler = ^{
                    [weakSelf presentActionPanelForElement:element
                                             forwardTarget:weakTarget
                                                sourceView:weakSource];
                };
            }
            overlay = button;
        } else {
            UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
            imageView.frame = frame;
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            imageView.tintColor = target.sourceView.tintColor ?: rootView.tintColor;
            imageView.userInteractionEnabled = NO;
            overlay = imageView;
        }
        if ([element[@"template"] boolValue]) {
            if ([overlay isKindOfClass:UIImageView.class]) ((UIImageView *)overlay).image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            if ([overlay isKindOfClass:UIButton.class]) [(UIButton *)overlay setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        }
        [host addSubview:overlay];
        if (target.sourceView) [self hideOriginalView:target.sourceView inRoot:rootView];
    }
    [CATransaction commit];
    [CATransaction flush];
}

@end
