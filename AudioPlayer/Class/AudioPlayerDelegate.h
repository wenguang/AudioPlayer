//
//  AudioPlayerDelegate.h
//  AudioPlayer
//
//  Created by wenguang pan on 12/8/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AudioPlayer;

@protocol AudioPlayerDelegate <NSObject>

- (void) audioPlayer:(AudioPlayer *)audioPlayer didFailWithErrorReason:(NSString *)reason;
- (void) audioPlayer:(AudioPlayer *)audioPlayer didStateChangedWithNewState:(SInt8)state;

@end
