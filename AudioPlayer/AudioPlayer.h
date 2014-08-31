//
//  AudioPlayer.h
//  AudioPlayer
//
//  Created by wenguang pan on 10/21/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import "AudioPlayerDelegate.h"

#define kNumOfBuffers 3

typedef enum : SInt8
{
    kAudioPlayStateInitialized = 0,
    kAudioPlayStatePlayning = 1,
    kAudioPlayStatePaused = 2,
    kAudioPlayStateStopped = 3,
    kAudioPlayStateBuffering = 4,
    kAudioPlayStateOther = 5
    
} AQSPlayState;

typedef enum
{
    kAudioSourceFromLocal,
    kAudioSourceFromHttp
    
} AQSAudioSource;

@interface AudioPlayer : NSObject
{
    NSThread *_streamThread;
    
    id<AudioPlayerDelegate> _delegate;
    
    //
    // audio queue vars
    //
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef _audioQueueBuffers[kNumOfBuffers];
    
    //
    // audio file vars
    //
    AudioFileID _audioFileID;
    
    //
    // audio file stream vars
    //
    AudioFileStreamID _audioFileStreamID;
    UInt32 _audioDataFormatID;
    UInt32 _bitRate;
    UInt32 _maxPacketSize;
    UInt64 _audioDataByteCount;
    //UInt64 audioDataPacketCount;
    SInt64 _audioDataOffset;
    SInt32 _currentPacket;
    UInt32 _bufferByteSize;
    UInt32 _numPacketToRead;
    UInt64 _numOfPackets;
    
    NSMutableArray *_audioStreamBufferArray;
    UInt32 _bufferUsedIndex;
    
    //
    // audio data format vars
    //
    AudioStreamBasicDescription _asbd;
    AudioStreamPacketDescription _aspd;
    BOOL _isVBR;
    
    //
    // playing time vars
    //
    UInt32 _estimatedDuration;
    float _currentTime;
    
    //
    // state controlling vars
    //
    AQSPlayState _playState;
    BOOL _isLoop;
    AQSAudioSource _audioSource;
    
    //
    // audio uri vars
    //
    NSString *_audioPath;
    NSURL *_audioURL;
    
    //
    // http stream vars
    //
    CFReadStreamRef _readStream;
    CFHTTPMessageRef _httpRequest;
    NSDictionary *_responseHeader;
    long _fileLength;    
    long _contentLength;
    long _seekOffset;
    
    
    //
    // error
    //
    OSStatus _err;
}

- (id)initWithAudioPath:(NSString *)theAudioPath delegate:(id<AudioPlayerDelegate>)theDelegate;
- (void)start;
- (void)stop;
- (void)pause;


@end
