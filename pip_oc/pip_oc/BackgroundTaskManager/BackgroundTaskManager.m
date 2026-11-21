#import "BackgroundTaskManager.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface BackgroundTaskManager()

@property (strong, nonatomic) AVAudioPlayer *audioPlayer;

@end

@implementation BackgroundTaskManager

/// Tạo singleton
+ (BackgroundTaskManager *)shareManager
{
   static BackgroundTaskManager *manager = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
       manager = [[BackgroundTaskManager alloc]init];
   });
   return manager;
}

/// Bắt đầu phát âm thanh
- (void)startPlayAudioSession
{
   [self.audioPlayer play];
}

/// Dừng phát âm thanh
- (void)stopPlayAudioSession
{
   [self.audioPlayer stop];
}

- (AVAudioPlayer *)audioPlayer
{
    if (!_audioPlayer) {
        //Cho phép tiếp tục phát khi ở chế độ nền và khóa màn hình
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        [[AVAudioSession sharedInstance] setActive: YES error: nil];
        //Khởi tạo trình phát âm thanh
        NSError *playerError;
        NSURL *urlSound = [[NSURL alloc]initWithString:[[NSBundle mainBundle]pathForResource:@"slience" ofType:@"mp3"]];
        _audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:urlSound error:&playerError];
        _audioPlayer.numberOfLoops = -1;//Phát vô hạn
        _audioPlayer.volume = 0;
    }
    return _audioPlayer;
}

@end
