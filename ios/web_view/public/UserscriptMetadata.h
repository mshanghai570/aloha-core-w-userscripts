#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UserscriptMetadata : NSObject

@property(nonatomic, copy, readonly) NSString* name;
@property(nonatomic, copy, readonly) NSArray<NSString*>* matches;
@property(nonatomic, copy, readonly) NSString* runAt;

- (nullable instancetype)initWithUserscriptSource:(NSString*)source;

@end

NS_ASSUME_NONNULL_END
