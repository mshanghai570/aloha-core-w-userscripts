// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/chrome/browser/userscripts/ui/userscripts_manager_view_controller.h"

#import "base/memory/raw_ptr.h"
#import "base/metrics/user_metrics.h"
#import "base/metrics/user_metrics_action.h"
#import "base/strings/sys_string_conversions.h"
#import "components/strings/grit/components_strings.h"
#import "ios/chrome/browser/shared/model/profile/profile_ios.h"
#import "ios/chrome/browser/userscripts/model/userscript_parser.h"
#import "ios/chrome/browser/userscripts/model/userscripts_service.h"
#import "ios/chrome/browser/userscripts/model/userscripts_service_factory.h"
#import "ios/chrome/grit/ios_strings.h"
#import "ui/base/l10n/l10n_util_mac.h"
#import "url/gurl.h"

namespace {

constexpr NSUInteger kMaxImportedSourceBytes = 2 * 1024 * 1024;

NSString* ParseErrorMessage(userscripts::UserScriptParseError error) {
  switch (error) {
    case userscripts::UserScriptParseError::kSourceTooLarge:
    case userscripts::UserScriptParseError::kHeaderTooLarge:
      return l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_SOURCE_TOO_LARGE);
    case userscripts::UserScriptParseError::kHeaderMissing:
    case userscripts::UserScriptParseError::kHeaderUnterminated:
    case userscripts::UserScriptParseError::kNameMissing:
    case userscripts::UserScriptParseError::kMissingDirectiveValue:
    case userscripts::UserScriptParseError::kMalformedHeaderLine:
    case userscripts::UserScriptParseError::kInvalidRunAt:
    case userscripts::UserScriptParseError::kInvalidMatchPattern:
    case userscripts::UserScriptParseError::kInvalidExcludeMatchPattern:
      return l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_INVALID_SCRIPT);
  }
}

NSString* MetadataList(const std::vector<std::string>& values) {
  NSMutableArray<NSString*>* strings = [[NSMutableArray alloc] init];
  for (const std::string& value : values) {
    [strings addObject:base::SysUTF8ToNSString(value)];
  }
  return [strings componentsJoinedByString:@", "];
}

}  // namespace

@interface UserscriptEditorViewController : UIViewController
    <UITextViewDelegate>

- (instancetype)initWithProfile:(ProfileIOS*)profile
                         source:(NSString*)source
                       scriptID:(NSString*)scriptID;

@end

@implementation UserscriptEditorViewController {
  raw_ptr<userscripts::UserscriptsService> _service;
  NSString* _source;
  NSString* _scriptID;
  UITextView* _sourceView;
}

- (instancetype)initWithProfile:(ProfileIOS*)profile
                         source:(NSString*)source
                       scriptID:(NSString*)scriptID {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _service = userscripts::UserscriptsServiceFactory::GetForProfile(profile);
    _source = [source copy];
    _scriptID = [scriptID copy];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  self.title = _scriptID.length
                   ? l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_EDIT_TITLE)
                   : l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_ADD_TITLE);
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                           target:self
                           action:@selector(cancelEditing)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
      initWithTitle:l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_REVIEW_INSTALL)
              style:UIBarButtonItemStyleDone
             target:self
             action:@selector(reviewAndSave)];

  _sourceView = [[UITextView alloc] init];
  _sourceView.translatesAutoresizingMaskIntoConstraints = NO;
  _sourceView.font = [UIFont monospacedSystemFontOfSize:13
                                                 weight:UIFontWeightRegular];
  _sourceView.accessibilityIdentifier = @"UserscriptEditor.Source";
  _sourceView.text = _source ?: @"";
  [self.view addSubview:_sourceView];
  [NSLayoutConstraint activateConstraints:@[
    [_sourceView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_sourceView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_sourceView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [_sourceView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
  ]];
}

- (void)cancelEditing {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)reviewAndSave {
  const std::string source = base::SysNSStringToUTF8(_sourceView.text ?: @"");
  auto parsed = userscripts::ParseUserScript(source);
  if (!parsed) {
    [self showMessage:ParseErrorMessage(parsed.error())
                title:l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_ERROR_TITLE)];
    return;
  }

  NSMutableString* preview = [[NSMutableString alloc] initWithFormat:@"%@\n%@",
      base::SysUTF8ToNSString(parsed->metadata.name),
      l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_REQUESTED_GRANTS)];
  NSString* grants = MetadataList(parsed->metadata.grants);
  [preview appendFormat:@"\n%@", grants.length ? grants : @"none"];
  if (!parsed->unsupported_grants.empty() ||
      !parsed->unsupported_directives.empty()) {
    [preview appendFormat:@"\n\n%@\n%@%@",
        l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_UNSUPPORTED_WARNING),
        MetadataList(parsed->unsupported_grants),
        parsed->unsupported_directives.empty()
            ? @""
            : [NSString stringWithFormat:@" %@",
                                         MetadataList(parsed->unsupported_directives)]];
  }

  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:l10n_util::GetNSString(
                                   IDS_IOS_USERSCRIPTS_REVIEW_TITLE)
                       message:preview
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(IDS_CANCEL)
                                 style:UIAlertActionStyleCancel
                               handler:nil]];
  __weak __typeof(self) weakSelf = self;
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(
                                           IDS_IOS_USERSCRIPTS_INSTALL_ACTION)
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction*) {
                                 [weakSelf installSource:source];
                               }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)installSource:(const std::string&)source {
  if (!_service) {
    [self showMessage:l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_SAVE_ERROR)
                title:l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_ERROR_TITLE)];
    return;
  }
  auto result = _service->InstallScript(source, GURL());
  if (!result) {
    [self showMessage:l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_SAVE_ERROR)
                title:l10n_util::GetNSString(IDS_IOS_USERSCRIPTS_ERROR_TITLE)];
    return;
  }
  if (_scriptID.length &&
      base::SysNSStringToUTF8(_scriptID) != result.value()) {
    _service->RemoveScript(base::SysNSStringToUTF8(_scriptID));
  }
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)showMessage:(NSString*)message title:(NSString*)title {
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:title
                       message:message
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(IDS_OK)
                                 style:UIAlertActionStyleDefault
                               handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation UserscriptsManagerViewController {
  raw_ptr<ProfileIOS> _profile;
  raw_ptr<userscripts::UserscriptsService> _service;
  std::vector<userscripts::StoredUserScript> _scripts;
}

- (instancetype)initWithProfile:(ProfileIOS*)profile {
  self = [super initWithStyle:UITableViewStyleInsetGrouped];
  if (self) {
    _profile = profile;
    _service = userscripts::UserscriptsServiceFactory::GetForProfile(profile);
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = l10n_util::GetNSString(IDS_IOS_SETTINGS_USERSCRIPTS_TITLE);
  self.tableView.accessibilityIdentifier = @"Userscripts.Manager.Table";
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                           target:self
                           action:@selector(addScript)];
  [self reloadScripts];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self reloadScripts];
}

- (void)reloadScripts {
  _scripts.clear();
  if (_service) {
    auto scripts = _service->GetScripts();
    if (scripts) {
      _scripts = std::move(scripts.value());
    }
  }
  [self.tableView reloadData];
}

- (void)addScript {
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:l10n_util::GetNSString(
                                   IDS_IOS_USERSCRIPTS_ADD_TITLE)
                       message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];
  __weak __typeof(self) weakSelf = self;
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(
                                           IDS_IOS_USERSCRIPTS_ENTER_SOURCE)
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction*) {
                                 NSString* template =
                                     @"// ==UserScript==\n// @name Example\n"
                                      @"// @match https://example.com/*\n"
                                      @"// @grant none\n"
                                      @"// ==/UserScript==\n\n";
                                 UserscriptEditorViewController* editor =
                                     [[UserscriptEditorViewController alloc]
                                         initWithProfile:weakSelf->_profile
                                                 source:template
                                               scriptID:nil];
                                 [weakSelf.navigationController
                                     pushViewController:editor
                                               animated:YES];
                               }]];
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(
                                           IDS_IOS_USERSCRIPTS_IMPORT_FILE)
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction*) {
                                 [weakSelf presentFilePicker];
                               }]];
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(IDS_CANCEL)
                                 style:UIAlertActionStyleCancel
                               handler:nil]];
  alert.popoverPresentationController.barButtonItem =
      self.navigationItem.rightBarButtonItem;
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentFilePicker {
  UIDocumentPickerViewController* picker =
      [[UIDocumentPickerViewController alloc]
          initWithDocumentTypes:@[@"public.text", @"public.plain-text"]
                         inMode:UIDocumentPickerModeImport];
  picker.delegate = (id<UIDocumentPickerDelegate>)self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  NSURL* url = urls.firstObject;
  if (!url) {
    return;
  }
  const BOOL didStartAccess = [url startAccessingSecurityScopedResource];
  NSError* error = nil;
  NSData* data = [NSData dataWithContentsOfURL:url
                                       options:NSDataReadingMappedIfSafe
                                         error:&error];
  NSString* source = nil;
  if (data.length <= kMaxImportedSourceBytes) {
    source = [[NSString alloc] initWithData:data
                                   encoding:NSUTF8StringEncoding];
  }
  if (didStartAccess) {
    [url stopAccessingSecurityScopedResource];
  }
  if (!data || data.length > kMaxImportedSourceBytes || !source) {
    [self showImportError];
    return;
  }
  UserscriptEditorViewController* editor =
      [[UserscriptEditorViewController alloc] initWithProfile:_profile
                                                       source:source
                                                     scriptID:nil];
  [self.navigationController pushViewController:editor animated:YES];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
  [controller dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView*)tableView
    numberOfRowsInSection:(NSInteger)section {
  return _scripts.size();
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  static NSString* const identifier = @"UserscriptCell";
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifier];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                  reuseIdentifier:identifier];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }
  const userscripts::StoredUserScript& script = _scripts[indexPath.row];
  cell.textLabel.text = base::SysUTF8ToNSString(script.parsed.metadata.name);
  NSString* version = base::SysUTF8ToNSString(script.parsed.metadata.version);
  cell.detailTextLabel.text = [NSString
      stringWithFormat:@"%@ · %@",
                       version.length ? version : @"",
                       script.enabled
                           ? l10n_util::GetNSString(
                                 IDS_IOS_USERSCRIPTS_ENABLED)
                           : l10n_util::GetNSString(
                                 IDS_IOS_USERSCRIPTS_DISABLED)];
  cell.accessibilityIdentifier = [NSString
      stringWithFormat:@"Userscripts.Manager.Script.%@",
                       base::SysUTF8ToNSString(script.id)];
  UISwitch* toggle = [[UISwitch alloc] init];
  toggle.on = script.enabled;
  toggle.tag = indexPath.row;
  toggle.accessibilityLabel = cell.textLabel.text;
  toggle.accessibilityIdentifier = [NSString
      stringWithFormat:@"Userscripts.Manager.Toggle.%@",
                       base::SysUTF8ToNSString(script.id)];
  [toggle addTarget:self
                action:@selector(toggleScript:)
      forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = toggle;
  return cell;
}

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  const userscripts::StoredUserScript& script = _scripts[indexPath.row];
  UserscriptEditorViewController* editor =
      [[UserscriptEditorViewController alloc]
          initWithProfile:_profile
                   source:base::SysUTF8ToNSString(script.parsed.source)
                 scriptID:base::SysUTF8ToNSString(script.id)];
  [self.navigationController pushViewController:editor animated:YES];
}

- (void)tableView:(UITableView*)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath*)indexPath {
  if (editingStyle != UITableViewCellEditingStyleDelete) {
    return;
  }
  const std::string scriptID = _scripts[indexPath.row].id;
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:l10n_util::GetNSString(
                                   IDS_IOS_USERSCRIPTS_DELETE_TITLE)
                       message:l10n_util::GetNSString(
                                   IDS_IOS_USERSCRIPTS_DELETE_MESSAGE)
                preferredStyle:UIAlertControllerStyleAlert];
  __weak __typeof(self) weakSelf = self;
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(IDS_CANCEL)
                                 style:UIAlertActionStyleCancel
                               handler:nil]];
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(
                                           IDS_IOS_USERSCRIPTS_DELETE_ACTION)
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction*) {
                                 auto result = weakSelf->_service->RemoveScript(scriptID);
                                 if (!result) {
                                   [weakSelf showImportError];
                                   return;
                                 }
                                 [weakSelf reloadScripts];
                               }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleScript:(UISwitch*)sender {
  if (sender.tag < 0 || sender.tag >= static_cast<NSInteger>(_scripts.size()) ||
      !_service) {
    return;
  }
  const userscripts::StoredUserScript& script = _scripts[sender.tag];
  auto result = _service->SetEnabled(script.id, sender.on);
  if (!result) {
    sender.on = !sender.on;
    [self showImportError];
    return;
  }
  [self reloadScripts];
}

- (void)showImportError {
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:l10n_util::GetNSString(
                                   IDS_IOS_USERSCRIPTS_ERROR_TITLE)
                       message:l10n_util::GetNSString(
                                   IDS_IOS_USERSCRIPTS_SAVE_ERROR)
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction
                       actionWithTitle:l10n_util::GetNSString(IDS_OK)
                                 style:UIAlertActionStyleDefault
                               handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)reportDismissalUserAction {
  base::RecordAction(base::UserMetricsAction("Settings.Userscripts.Dismiss"));
}

- (void)reportBackUserAction {
  base::RecordAction(base::UserMetricsAction("Settings.Userscripts.Back"));
}

@end
