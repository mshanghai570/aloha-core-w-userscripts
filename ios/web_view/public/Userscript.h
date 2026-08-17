#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Userscript : NSObject

@property(nonatomic, copy, readonly) NSString* name;
@property(nonatomic, copy, readonly) NSString* source;

- (instancetype)initWithContentsOfFile:(NSString*)path error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
