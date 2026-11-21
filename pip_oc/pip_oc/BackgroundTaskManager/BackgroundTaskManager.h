#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BackgroundTaskManager : NSObject

/// Tạo singleton
+ (BackgroundTaskManager *)shareManager;

/// Bắt đầu phát nhạc
- (void)startPlayAudioSession;

/// Dừng phát nhạc
- (void)stopPlayAudioSession;

@end

NS_ASSUME_NONNULL_END
