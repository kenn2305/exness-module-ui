#import <PhotosUI/PhotosUI.h>
#import "MUIDesignerViewController.h"
#import "MUIConfigStore.h"
#import "MUIModule.h"
#import "MUIPreviewView.h"
#import "MUIRuntime.h"

@interface MUIDesignerViewController () <UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, weak) MUIRuntime *runtime;
@property (nonatomic, strong) NSMutableArray<MUIModule *> *modules;
@property (nonatomic, strong) MUIPreviewView *previewView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy, nullable) NSString *iconTargetModuleID;
@end

@implementation MUIDesignerViewController

- (instancetype)initWithRuntime:(MUIRuntime *)runtime {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _runtime = runtime;
        _modules = [[runtime editableSnapshot] mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Exness UI Designer";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(applyTapped)];

    self.previewView = [[MUIPreviewView alloc] init];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    UITabBar *sourceTabBar = self.runtime.tabBarController.tabBar;
    if (sourceTabBar.tintColor) self.previewView.tintColor = sourceTabBar.tintColor;
    UIColor *sourceBackground = sourceTabBar.standardAppearance.backgroundColor;
    if (sourceBackground) self.previewView.backgroundColor = sourceBackground;

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = @"This preview is cloned from Exness live native tabs. Drag rows to reorder; tap a row to rename or replace its icon.";
    hint.numberOfLines = 0;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    hint.textColor = UIColor.secondaryLabelColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.editing = YES;
    self.tableView.rowHeight = 58.0;

    [self.view addSubview:self.previewView];
    [self.view addSubview:hint];
    [self.view addSubview:self.tableView];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.previewView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16.0],
        [self.previewView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [self.previewView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [self.previewView.heightAnchor constraintEqualToConstant:82.0],
        [hint.topAnchor constraintEqualToAnchor:self.previewView.bottomAnchor constant:10.0],
        [hint.leadingAnchor constraintEqualToAnchor:self.previewView.leadingAnchor constant:4.0],
        [hint.trailingAnchor constraintEqualToAnchor:self.previewView.trailingAnchor constant:-4.0],
        [self.tableView.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:4.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self refreshPreview];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyTapped {
    NSError *error = nil;
    if (![self.runtime applyAndSaveModules:self.modules error:&error]) {
        [self showError:error.localizedDescription ?: @"The layout could not be applied."];
        return;
    }
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Exness Module UI"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (MUIModule *)moduleWithID:(NSString *)identifier {
    for (MUIModule *module in self.modules) {
        if ([module.identifier isEqualToString:identifier]) return module;
    }
    return nil;
}

- (UIImage *)displayImageForModule:(MUIModule *)module {
    if (module.customIconPath.length > 0) {
        UIImage *custom = [[MUIConfigStore sharedStore] imageAtRelativePath:module.customIconPath];
        if (custom) return [custom imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return module.originalImage ?: [UIImage systemImageNamed:@"square.grid.2x2"];
}

- (void)refreshPreview {
    [self.previewView renderModules:self.modules];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.modules.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Live Exness modules";
    if (section == 1) return @"Current screen";
    return @"Recovery";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Disabled modules stay in this list and can be restored at any time.";
    if (section == 1) return @"Edit buttons, images and text inside the current Exness screen.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"Edit icons in current screen";
        cell.detailTextLabel.text = @"Move, resize, replace, hide or add linked icons";
        cell.textLabel.textColor = self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:@"rectangle.3.group"];
        cell.showsReorderControl = NO;
        return cell;
    }
    if (indexPath.section == 2) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Reset original Exness layout";
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.counterclockwise"];
        cell.showsReorderControl = NO;
        return cell;
    }

    static NSString *identifier = @"ModuleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    MUIModule *module = self.modules[indexPath.row];
    cell.textLabel.text = module.displayTitle.length > 0 ? module.displayTitle : module.originalTitle;
    cell.detailTextLabel.text = module.controllerClass;
    cell.imageView.image = [self displayImageForModule:module];
    cell.imageView.tintColor = self.view.tintColor;
    cell.showsReorderControl = YES;

    UISwitch *visibleSwitch = [[UISwitch alloc] init];
    visibleSwitch.on = module.enabled;
    visibleSwitch.accessibilityLabel = [NSString stringWithFormat:@"Show %@", cell.textLabel.text];
    visibleSwitch.tag = indexPath.row;
    [visibleSwitch addTarget:self action:@selector(visibilityChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = visibleSwitch;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 0 || destinationIndexPath.section != 0) return;
    MUIModule *module = self.modules[sourceIndexPath.row];
    [self.modules removeObjectAtIndex:sourceIndexPath.row];
    [self.modules insertObject:module atIndex:destinationIndexPath.row];
    [self refreshPreview];
    [self.tableView reloadData];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section != 0) {
        return [NSIndexPath indexPathForRow:self.modules.count - 1 inSection:0];
    }
    return proposedDestinationIndexPath;
}

- (void)visibilityChanged:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.modules.count) return;
    self.modules[sender.tag].enabled = sender.isOn;
    [self refreshPreview];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self dismissViewControllerAnimated:YES completion:^{
            [self.runtime presentScreenEditor];
        }];
        return;
    }
    if (indexPath.section == 2) {
        [self confirmReset];
        return;
    }
    [self presentActionsForModule:self.modules[indexPath.row]];
}

#pragma mark - Editing actions

- (void)presentActionsForModule:(MUIModule *)module {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:module.displayTitle
                                                                   message:@"Edit this live Exness module"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentRenameForModule:module];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose icon from Photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentPhotoPickerForModule:module];
    }]];
    if (module.customIconPath.length > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Restore original icon" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            module.customIconPath = nil;
            [weakSelf.tableView reloadData];
            [weakSelf refreshPreview];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 40.0, 1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentRenameForModule:(MUIModule *)module {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename module"
                                                                   message:module.controllerClass
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = module.displayTitle;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (title.length > 0 && title.length <= 24) module.displayTitle = title;
        [weakSelf.tableView reloadData];
        [weakSelf refreshPreview];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentPhotoPickerForModule:(MUIModule *)module {
    self.iconTargetModuleID = module.identifier;
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    NSString *targetID = self.iconTargetModuleID;
    self.iconTargetModuleID = nil;
    if (!result || targetID.length == 0 || ![result.itemProvider canLoadObjectOfClass:UIImage.class]) return;

    __weak typeof(self) weakSelf = self;
    [result.itemProvider loadObjectOfClass:UIImage.class completionHandler:^(UIImage *image, NSError *loadError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (loadError || !image) {
                [weakSelf showError:loadError.localizedDescription ?: @"The selected image could not be loaded."];
                return;
            }
            NSError *saveError = nil;
            NSString *path = [[MUIConfigStore sharedStore] saveIconImage:image forModuleID:targetID error:&saveError];
            if (!path) {
                [weakSelf showError:saveError.localizedDescription ?: @"The icon could not be saved."];
                return;
            }
            MUIModule *module = [weakSelf moduleWithID:targetID];
            module.customIconPath = path;
            [weakSelf.tableView reloadData];
            [weakSelf refreshPreview];
        });
    }];
}

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Exness layout?"
                                                                   message:@"This restores the original order, names and icons captured from Exness."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error = nil;
        if (![weakSelf.runtime resetToOriginalWithError:&error]) {
            [weakSelf showError:error.localizedDescription ?: @"Reset failed."];
            return;
        }
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
