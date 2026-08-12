#import "MUIPreviewView.h"
#import "MUIConfigStore.h"
#import "MUIModule.h"

@interface MUIPreviewView ()
@property (nonatomic, strong) UIStackView *stackView;
@end

@implementation MUIPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self commonInit];
    return self;
}

- (void)commonInit {
    self.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.layer.cornerRadius = 16.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    _stackView = [[UIStackView alloc] init];
    _stackView.axis = UILayoutConstraintAxisHorizontal;
    _stackView.distribution = UIStackViewDistributionFillEqually;
    _stackView.alignment = UIStackViewAlignmentFill;
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stackView];
    [NSLayoutConstraint activateConstraints:@[
        [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
        [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
        [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
        [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0]
    ]];
}

- (UIImage *)imageForModule:(MUIModule *)module {
    if (module.customIconPath.length > 0) {
        UIImage *custom = [[MUIConfigStore sharedStore] imageAtRelativePath:module.customIconPath];
        if (custom) return [custom imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return module.originalImage ?: [UIImage systemImageNamed:@"square.grid.2x2"];
}

- (void)renderModules:(NSArray<MUIModule *> *)modules {
    for (UIView *view in self.stackView.arrangedSubviews.copy) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSPredicate *visiblePredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        MUIModule *module = (MUIModule *)object;
        return module.enabled;
    }];
    NSArray<MUIModule *> *visible = [modules filteredArrayUsingPredicate:visiblePredicate];
    for (MUIModule *module in visible) {
        UIStackView *item = [[UIStackView alloc] init];
        item.axis = UILayoutConstraintAxisVertical;
        item.alignment = UIStackViewAlignmentCenter;
        item.distribution = UIStackViewDistributionFill;
        item.spacing = 4.0;

        UIImageView *imageView = [[UIImageView alloc] initWithImage:[self imageForModule:module]];
        imageView.tintColor = self.tintColor;
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        [NSLayoutConstraint activateConstraints:@[
            [imageView.widthAnchor constraintEqualToConstant:25.0],
            [imageView.heightAnchor constraintEqualToConstant:25.0]
        ]];

        UILabel *label = [[UILabel alloc] init];
        label.text = module.displayTitle.length > 0 ? module.displayTitle : module.originalTitle;
        label.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
        label.textColor = UIColor.secondaryLabelColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.65;

        [item addArrangedSubview:imageView];
        [item addArrangedSubview:label];
        [self.stackView addArrangedSubview:item];
    }

    if (visible.count == 0) {
        UILabel *empty = [UILabel new];
        empty.text = @"At least one module must be visible";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.systemRedColor;
        empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        [self.stackView addArrangedSubview:empty];
    }
}

@end
