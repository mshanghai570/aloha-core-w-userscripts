#import "ios/web_view/public/Userscript.h"

@implementation Userscript

- (instancetype)initWithContentsOfFile:(NSString*)path error:(NSError**)error {
  self = [super init];
  if (!self) return nil;
  NSError* readError = nil;
  NSString* contents = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:&readError];
  if (!contents) {
    if (error) *error = readError;
    return nil;
  }
  _source = [contents copy];
  _name = [[path lastPathComponent] copy];
  return self;
}

@end
