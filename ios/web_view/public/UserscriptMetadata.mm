#import "ios/web_view/public/UserscriptMetadata.h"

@implementation UserscriptMetadata

- (instancetype)initWithUserscriptSource:(NSString*)source {
  self = [super init];
  if (!self) return nil;
  // Minimal stub: populate with defaults. Real implementation should parse
  // the metadata block in the userscript source.
  _name = @"Unnamed";
  _matches = @[@"*://*/*"];
  _runAt = @"document-end";
  (void)source;
  return self;
}

@end
