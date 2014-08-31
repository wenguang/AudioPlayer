//
//  AudioPlayer.m
//  AudioPlayer
//
//  Created by wenguang pan on 10/21/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import "AudioPlayer.h"
#import "AudioStreamBuffer.h"

#define kAudioTime .5
#define kMaxAudioBufferSize 0x10000
#define kMinAudioBufferSize 0x4000
#define kDefaultNumOfPacketDescsForAudioBuffer 10
#define kDefaultStreamBufferSize 4096
#define kDefaultAudioStreamBufferArrayCapacity 100

#if TARGET_OS_IPHONE
NSString * const AudioSessionInterruptionNotification = @"AudioSessionInterruptionNotification";
NSString * const AudioSessionInterruptionTypeKey      = @"AudioSessionInterruptionTypeKey";
NSString * const AudioSessionInterruptionStateKey     = @"AudioSessionInterruptionStateKey";
NSString * const AudioSessionPropertyNotification     = @"AudioSessionPropertyNotification";
NSString * const AudioSessionPropertyOtherAudioIsPlayingKey = @"AudioSessionPropertyOtherAudioIsPlayingKey";
#endif

NSString * const DefaultErrorReason = @"error";

@interface AudioPlayer ()

- (void) startAudioSession;

//
// declarations of methods calls by callback methods, must be declared before callbacks
//

- (void) handleAudioQueueOutputCallback:(AudioQueueRef)queue audioBuffer:(AudioQueueBufferRef)buffer;

- (void) handleAudioQueuePropertyListenerProc:(AudioQueueRef)queue propertyID:(AudioQueuePropertyID)propertyID;

#if TARGET_OS_IPHONE
- (void) handleAudioSessionInterruptionListenerProc:(AudioSessionInterruptionType)type interruptionState:(UInt32)state;

- (void) handleAudioSessionPropertyListenerProc:(AudioSessionPropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data;
#endif

- (void) handleAudioStreamPacketsProc:(UInt32)numBytes numPackets:(UInt32)numPackets inputData:(const void *)inputData packetDescs:(AudioStreamPacketDescription *)packetDescs;

- (void) handleAudioStreamPropertyListenerProc:(AudioFileStreamID)streamID propertyID:(AudioFileStreamPropertyID)propertyID flags:(UInt32 *)flags;

- (void) handleAudioStreamReadCallback:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType;

//
// err handle func
//
- (void) failWithErrorReason:(NSString *)reason;

@end


//
// callback methods
//

static void AudioQueue_OutputCallback(void * inUserData, AudioQueueRef inQueue, AudioQueueBufferRef inBuffer)
{
    AudioPlayer *player = (__bridge AudioPlayer *)inUserData;
    [player handleAudioQueueOutputCallback:inQueue audioBuffer:inBuffer];
}

static void AudioQueue_PropertyListenerProc(void * inUserData, AudioQueueRef inQueue, AudioQueuePropertyID inPropertyID)
{
    AudioPlayer *player = (__bridge AudioPlayer *)inUserData;
    [player handleAudioQueuePropertyListenerProc:inQueue propertyID:inPropertyID];
}

#if TARGET_OS_IPHONE
static void AudioSession_InterruptionListenerProc(void * inUserData, UInt32 inInterruptionState)
{
    UInt32 size;
    AudioSessionInterruptionType type;
    AudioSessionGetProperty(kAudioSessionProperty_InterruptionType, &size, &type);
    
    AudioPlayer *player = (__bridge AudioPlayer *)inUserData;
    [player handleAudioSessionInterruptionListenerProc:type interruptionState:inInterruptionState];
}

static void AudioSession_PropertyListenerProc(void * inUserData, AudioSessionPropertyID inID, UInt32 inDataSize, const void *inData)
{
    AudioPlayer *player = (__bridge AudioPlayer *)inUserData;
    [player handleAudioSessionPropertyListenerProc:inID dataSize:inDataSize data:inData];
}
#endif

static void AudioStream_PropertyListenerProc(void * inUserData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 * ioFlags)
{
    AudioPlayer *player = (__bridge AudioPlayer *)inUserData;
    [player handleAudioStreamPropertyListenerProc:inAudioFileStream propertyID:inPropertyID flags:ioFlags];
}

static void AudioStream_PacketsProc(void * inUserData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void * inInputData, AudioStreamPacketDescription * inPacketDescriptions)
{
    AudioPlayer *player = (__bridge AudioPlayer *)inUserData;
    [player handleAudioStreamPacketsProc:inNumberBytes numPackets:inNumberPackets inputData:inInputData packetDescs:inPacketDescriptions];
}

static void AudioStream_ReadCallback(CFReadStreamRef stream, CFStreamEventType eventType, void * userInfo)
{
    AudioPlayer *player = (__bridge AudioPlayer *)userInfo;
    [player handleAudioStreamReadCallback:stream eventType:eventType];
}

@implementation AudioPlayer

//
// helper methods
//
- (AudioFileTypeID) getAudioType
{
    return kAudioFileMP3Type;
}

- (void) failWithErrorReason:(NSString *)reason
{
    if (_delegate && [_delegate respondsToSelector:@selector(audioPlayer:didFailWithErrorReason:)])
    {
        [_delegate audioPlayer:self didFailWithErrorReason:reason];
    }

}

- (void) changeStateWithNewState:(SInt8)theState
{
    _playState = (AQSPlayState)theState;
    if (_delegate && [_delegate respondsToSelector:@selector(audioPlayer:didStateChangedWithNewState:)])
    {
        [_delegate audioPlayer:self didStateChangedWithNewState:theState];
    }
}

//
// methods calls by callbacks
//

- (void) handleAudioQueuePropertyListenerProc:(AudioQueueRef)queue propertyID:(AudioQueuePropertyID)propertyID
{
    
}

- (void) handleAudioSessionInterruptionListenerProc:(AudioSessionInterruptionType)type interruptionState:(UInt32)state
{
    NSDictionary *useInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSString stringWithFormat:@"%ld", type],
                             AudioSessionInterruptionTypeKey,
                             [NSString stringWithFormat:@"%ld", state],
                             AudioSessionInterruptionStateKey,
                             nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:AudioSessionInterruptionNotification object:self userInfo:useInfo];
}

- (void) handleAudioSessionPropertyListenerProc:(AudioSessionPropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data
{
    if (propertyID == kAudioSessionProperty_OtherAudioIsPlaying)
    {
        UInt32 flag = (UInt32)data;
        [[NSNotificationCenter defaultCenter] postNotificationName:AudioSessionPropertyNotification object:self userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%ld", flag] forKey:AudioSessionPropertyOtherAudioIsPlayingKey]];
    }
    else if (propertyID == kAudioSessionProperty_AudioRouteChange)
    {
        CFDictionaryRef routeChangeDic = (CFDictionaryRef)data;
        
        CFRelease(routeChangeDic);
    }
}

- (void) handleAudioQueueOutputCallback:(AudioQueueRef)queue audioBuffer:(AudioQueueBufferRef)buffer
{
    // update playback progress
    _currentTime += (_estimatedDuration * buffer->mPacketDescriptionCount / _numOfPackets);
    
    // user data of buffer for testing
    //int i = (int)buffer->mUserData;
    //NSLog(@"\n %d Buffer \n Current Packet : %ld \n", i, _currentPacket);
    
    UInt32 nPacket = _numPacketToRead;
    UInt32 numBytes;
    AudioFileReadPackets(_audioFileID, false, &numBytes, buffer->mPacketDescriptions, _currentPacket, &nPacket, buffer->mAudioData);
    
    if (nPacket == 0)
    {
        if (_isLoop)
        {
            _currentPacket = 0;
            _currentTime = 0.0f;
            //AQOutputCallback(self, inQueue, inBuffer);
        }
        else 
        {
            AudioQueueStop(queue, false);
        }
    }
    else 
    {
        buffer->mAudioDataByteSize = numBytes;
        buffer->mPacketDescriptionCount = nPacket;
        
        AudioQueueEnqueueBuffer(queue, buffer, _isVBR ? _numPacketToRead : 0, _isVBR ? buffer->mPacketDescriptions : NULL);
        
        _currentPacket += nPacket;
        
        //THIS->mCurrentTime += (THIS->mEstimatedDuration * nPacket / THIS->mNumOfPackets);
    }
}

- (void) handleAudioStreamPacketsProc:(UInt32)numBytes numPackets:(UInt32)numPackets inputData:(const void *)inputData packetDescs:(AudioStreamPacketDescription *)packetDescs
{
    if (_audioStreamBufferArray == nil)
    {
        _audioStreamBufferArray = [NSMutableArray arrayWithCapacity:kDefaultAudioStreamBufferArrayCapacity];
        _bufferUsedIndex = 0;
    }
    
    AudioStreamBuffer *asBuffer = [[AudioStreamBuffer alloc] initWithNumBytes:numBytes audioData:inputData numPackets:numPackets packetDescs:packetDescs];
    [_audioStreamBufferArray addObject:asBuffer];
    //asBuffer = nil;
    
    if (!_audioQueue && [_audioStreamBufferArray count] > 10)
    {
        [self initQueueForStream];
        
        for (int i=0; i<kNumOfBuffers; i++) 
        {
            AudioQueue_OutputCallback((__bridge void *)self, _audioQueue, _audioQueueBuffers[i]);
        }
        
        AudioQueueStart(_audioQueue, NULL);
    }
}

- (void) handleAudioStreamPropertyListenerProc:(AudioFileStreamID)streamID propertyID:(AudioFileStreamPropertyID)propertyID flags:(UInt32 *)flags
{
    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets)
    {
        return;
    }
    else if (propertyID == kAudioFileStreamProperty_AudioDataByteCount)
    {
        //
        // 6244310 for testing url
        //
        UInt32 size = sizeof(_audioDataByteCount);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, propertyID, &size, &_audioDataByteCount);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
    }
    else if (propertyID == kAudioFileStreamProperty_AudioDataPacketCount)
    {
        UInt32 size = sizeof(_numOfPackets);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, propertyID, &size, &_numOfPackets);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return; 
        }
    }
    
    else if (propertyID == kAudioFileStreamProperty_BitRate)
    {
        UInt32 size = sizeof(_bitRate);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, propertyID, &size, &_bitRate);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return; 
        }
    }
    else if (propertyID == kAudioFileStreamProperty_DataFormat)
    {
        UInt32 size = sizeof(_asbd);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, propertyID, &size, &_asbd);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return; 
        }
        
        _isVBR = (_asbd.mBytesPerPacket == 0);
    }
    else if (propertyID == kAudioFileStreamProperty_DataOffset)
    {
        SInt64 offset;
        UInt32 size = sizeof(offset);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, propertyID, &size, &offset);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return; 
        }
        _audioDataOffset = offset;
        return;
    }
    else if (propertyID == kAudioFileStreamProperty_FileFormat) // audio data format IDs defined in CoreAudioTypes.h
    {
        UInt32 size = sizeof(_audioDataFormatID);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, propertyID, &size, &_audioDataFormatID);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return; 
        }
    }
    else if (propertyID == kAudioFileStreamProperty_FormatList)
    {
        // TO DO ...
        return;
    }
}

- (void) handleAudioStreamReadCallback:(CFReadStreamRef)stream eventType:(CFStreamEventType)eventType
{
    if (eventType == kCFStreamEventOpenCompleted)
    {
        return;
    }
    else if (eventType == kCFStreamEventErrorOccurred)
    {
        [self cleanUpResouces];
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    else if (eventType == kCFStreamEventEndEncountered)
    {
        //
        // don't release stream instead of releasing readStream, thought they are equal
        //
        [self cleanUpResouces];    
        return;
    }
    else if (eventType == kCFStreamEventHasBytesAvailable)
    {
        if (!_responseHeader)
        {
            CFTypeRef message = CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
            _responseHeader = (__bridge_transfer NSDictionary *)CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message);
            CFRelease(message);
            
            //
            // 6276126 for testing url
            //
            _contentLength = [[_responseHeader objectForKey:@"Content-Length"] intValue];
        }
        
        
        if (!_audioFileStreamID)
        {
            _err = AudioFileStreamOpen((__bridge void *)self, AudioStream_PropertyListenerProc, AudioStream_PacketsProc, [self getAudioType], &_audioFileStreamID);
            if (_err)
            {
                [self failWithErrorReason:DefaultErrorReason];
                return;
            }
        }
        
        UInt8 buffer[kDefaultStreamBufferSize];
        CFIndex length = CFReadStreamRead(stream, buffer, kDefaultStreamBufferSize);
        if (length <= 0)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        
        _err = AudioFileStreamParseBytes(_audioFileStreamID, length, buffer, 0);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
    }
}


/*********************************  Network Stream Processes  ********************************/

- (BOOL) openHttpStreamForAudio
{
    //
    // don't use "__bridge_retained" here, as audioURL will be used further
    //
    CFURLRef url = (__bridge_retained CFURLRef)_audioURL;
    _httpRequest = CFHTTPMessageCreateRequest(CFAllocatorGetDefault(), CFSTR("GET"), url, kCFHTTPVersion1_1);
    CFRelease(url);
    
    _seekOffset = 0;
    if (_seekOffset > 0)
    {
        //
        // contentLength for testing url is 6276126
        //
        CFHTTPMessageSetHeaderFieldValue(_httpRequest, CFSTR("Range"), (__bridge CFStringRef)[NSString stringWithFormat:@"bytes=%ld-6276126", _seekOffset]);
    }
    
    CFOptionFlags streamEvents = kCFStreamEventCanAcceptBytes | kCFStreamEventEndEncountered | kCFStreamEventErrorOccurred | kCFStreamEventHasBytesAvailable | kCFStreamEventOpenCompleted;
    
    _readStream = CFReadStreamCreateForHTTPRequest(NULL, _httpRequest);
    
    CFStreamClientContext context  = {0, (__bridge void *)self, NULL, NULL, NULL};
    CFReadStreamSetClient(_readStream, streamEvents, AudioStream_ReadCallback, &context);
    CFReadStreamScheduleWithRunLoop(_readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    return CFReadStreamOpen(_readStream);
}

- (void) cleanUpResouces
{
    if (_audioSource == kAudioSourceFromHttp)
    {
        if (_httpRequest)
        {
            CFRelease(_httpRequest); // occur [Not A Type release]: message sent to deallocated instance
            _httpRequest = NULL;
        }
        
        if (_readStream)
        {
            CFReadStreamUnscheduleFromRunLoop(_readStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
            CFReadStreamClose(_readStream);
            CFRelease(_readStream);
            _readStream = NULL;
        }
    }
    else
    {
        _audioFileID = 0;
    }
    
    _contentLength = 0;
    _responseHeader = nil;
    _currentPacket = 0;
    _bufferByteSize = 0;
    _maxPacketSize = 0;
    _numPacketToRead = 0;
    _estimatedDuration = 0;
    _currentTime = 0.0f;
    //_isLoop = false;
    
    //_audioQueue = NULL;
}


/*********************************            Initialize Methods        ********************************/

- (id) initWithAudioPath:(NSString *)theAudioPath delegate:(id<AudioPlayerDelegate>)theDelegate
{
    if (self = [super init]) 
    {
        _audioPath = theAudioPath;
        
        if ([theAudioPath rangeOfString:@"http://"].location != NSNotFound)
        {
            _audioSource = kAudioSourceFromHttp;
        }
        else
        {
            _audioSource = kAudioSourceFromLocal;
        }
        
        if (theDelegate && [theDelegate conformsToProtocol:@protocol(AudioPlayerDelegate)])
        {
            _delegate = theDelegate;
        }
        
        [self changeStateWithNewState:kAudioPlayStateInitialized];
    }
    return self;
}

#if TARGET_OS_IPHONE
- (void) startAudioSession
{
    _err = AudioSessionInitialize(CFRunLoopGetCurrent(), kCFRunLoopCommonModes, NULL, (__bridge void *)self);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
    _err = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    _err = AudioSessionAddPropertyListener(kAudioSessionProperty_OtherAudioIsPlaying, AudioSession_PropertyListenerProc, (__bridge void *)self);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    _err = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, AudioSession_PropertyListenerProc, (__bridge void *)self);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    _err = AudioSessionSetActive(true);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
}
#endif

- (void) streamThreadEntry
{
    @autoreleasepool 
    {
        
        if (![self openHttpStreamForAudio])
        {
            [self cleanUpResouces];
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        
#if TRAGET_OS_IPHONE
        [self startAudioSession];
#endif
        
        BOOL isRunning = YES;
        while (isRunning && !_err && _playState != kAudioPlayStateStopped) 
        {
            isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
            
            // to do... seek request
        }
        
        [self cleanUpResouces];
        
        AudioSessionSetActive(FALSE);
        
        //s_streamThread = nil;
        [self changeStateWithNewState:kAudioPlayStateInitialized];
    }
}

- (void) start
{
    if (_playState == kAudioPlayStateInitialized)
    {
        if (_audioSource == kAudioSourceFromHttp)
        {
            NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]], @"audio stream thread can't be started outside main thread");
            
            _streamThread = [[NSThread alloc] initWithTarget:self selector:@selector(streamThreadEntry) object:nil];
            [_streamThread start];
        }
        else 
        {
            [self initQueueForLocal];
            
            _err = AudioQueueStart(_audioQueue, NULL);
            if (_err)
            {
                [self failWithErrorReason:DefaultErrorReason];
                return;
            }
            
            [self changeStateWithNewState:kAudioPlayStatePlayning];
        }
    }
    else if (_playState == kAudioPlayStatePaused)
    {
        _err = AudioQueueStart(_audioQueue, NULL);
        if (_err)
        {
            [self failWithErrorReason:DefaultErrorReason];
            [self changeStateWithNewState:kAudioPlayStateOther];
            return;
        }
        [self changeStateWithNewState:kAudioPlayStatePlayning];
    }
    
    //
    // testing
    //

    //[self openHttpStreamForAudio];
    //return;
}

- (void) pause
{
    _err = AudioQueuePause(_audioQueue);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    
    [self changeStateWithNewState:kAudioPlayStatePaused];
}

- (void) stop
{
    // remove notification observers
    
    _err = AudioQueueStop(_audioQueue, false);
    
    [self disposeQueue];
    
    _playState = (_err == noErr ? kAudioPlayStateStopped : kAudioPlayStateOther);
}

- (void) disposeQueue
{
    //_filePath = NULL;
    _audioFileID = 0;
    _audioQueue = NULL;
}


/*********************************  Audio Queue Initialization Processes  ********************************/

- (void) initQueueForLocal
{
    // step 1
    [self openFileForQueue];
    // step 2
    [self deriveBufferSizeForLocal:_asbd maxPacketSize:_maxPacketSize seconds:kAudioTime outBufferSize:&_bufferByteSize outNumPacketsToRead:&_numPacketToRead outEstimatedTime:&_estimatedDuration];
    // step 3
    [self createQueue];
    // step 4
    [self configQueueForLocal];
    // step 5
    [self allocBuffers];
    
    _playState = kAudioPlayStateInitialized;
}

- (void) initQueueForStream
{
    [self deriveBufferSizeForStream];
    [self createQueue];
    [self configQueueForStream];
    [self allocBuffers];
}

// Init Audio Queue step 1: open an audio file and get properties for calculating size of buffer.
- (void) openFileForQueue
{
    // Open an audio file.
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)_audioPath, kCFURLPOSIXPathStyle, false);
    _err = AudioFileOpenURL(url, kAudioFileReadPermission, 0, &_audioFileID);
    CFRelease(url);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    
    // Read data format.
    UInt32 size = sizeof(_asbd);
    _err = AudioFileGetProperty(_audioFileID, kAudioFilePropertyDataFormat, &size, &_asbd);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    
    // Read max packet size.
    size = sizeof(_maxPacketSize);
    _err = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMaximumPacketSize, &size, &_maxPacketSize);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    
    // Read audio data packet count.
    size = sizeof(_numOfPackets);
    _err = AudioFileGetProperty(_audioFileID, kAudioFilePropertyAudioDataPacketCount, &size, &_numOfPackets);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
}

// Init Audio Queue step 2: calculate size of audio queue buffer according to time.
- (void) deriveBufferSizeForLocal:(AudioStreamBasicDescription)asbd maxPacketSize:(UInt32)maxPkgSize seconds:(Float64)seconds outBufferSize:(UInt32 *)outBufferSize outNumPacketsToRead:(UInt32 *)outNumPacketsToRead outEstimatedTime:(UInt32 *)outEstimatedTime
{
    if (asbd.mFramesPerPacket != 0) 
    {                             // 8
        Float64 numPacketsPerTime = asbd.mSampleRate * seconds / asbd.mFramesPerPacket; // number of packets per half second
        *outEstimatedTime = _numOfPackets / numPacketsPerTime * seconds;
        
        *outBufferSize = numPacketsPerTime * maxPkgSize;
    } 
    else 
    {                                                         // 9
        *outBufferSize = kMaxAudioBufferSize > maxPkgSize ? kMaxAudioBufferSize : maxPkgSize;
    }
    
    if (*outBufferSize > kMaxAudioBufferSize && *outBufferSize > maxPkgSize)
    {
        *outBufferSize = kMaxAudioBufferSize;
    }
    else 
    {                                                           // 11
        if (*outBufferSize < kMinAudioBufferSize)
            *outBufferSize = kMinAudioBufferSize;
    }
    
    *outNumPacketsToRead = *outBufferSize / maxPkgSize;           // 12
}

- (void) deriveBufferSizeForStream
{
     UInt32 size = sizeof(_maxPacketSize);
     _err = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &size, &_maxPacketSize);
     
     if (_err || size <= 0)
     {
         if (_err)  
         {
             [self failWithErrorReason:DefaultErrorReason];
         }
         _err = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &size, &_maxPacketSize);
         
         if (_err || size <= 0)
         {
             if (_err)  
             {
                 [self failWithErrorReason:DefaultErrorReason];
             }
             
             _maxPacketSize = 0;
         }
     }

    
    if (_asbd.mFramesPerPacket != 0) 
    {                             // 8
        Float64 numPacketsPerTime = _asbd.mSampleRate / _asbd.mFramesPerPacket * kAudioTime; // number of packets per half second
        _estimatedDuration = _numOfPackets / numPacketsPerTime * kAudioTime;
        
        if (_maxPacketSize > 0)
        {
            _bufferByteSize = numPacketsPerTime * _maxPacketSize;
        }
        else 
        {
            _bufferByteSize = kMaxAudioBufferSize;
        }
    }
    else 
    {
        // For formats with a variable number of frames per packet, such as Ogg Vorbis, asbd.mFramesPerPakcet equal 0
        
        if (_maxPacketSize > 0)
        {
            _bufferByteSize = _maxPacketSize > kMaxAudioBufferSize ? kMaxAudioBufferSize : _maxPacketSize < kMinAudioBufferSize ? kMinAudioBufferSize : _maxPacketSize;
        }
        else
        {
            _bufferByteSize = kMaxAudioBufferSize;
        }
    }
    
    _numPacketToRead = _maxPacketSize ? _bufferByteSize / _maxPacketSize : kDefaultNumOfPacketDescsForAudioBuffer;
}

// Init Audio Queue step3: create a new queue, and add property listener.
- (void) createQueue
{
    _err = AudioQueueNewOutput(&_asbd, AudioQueue_OutputCallback, (__bridge void *)self, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_audioQueue);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    _err = AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, 1.0);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    _err = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning, AudioQueue_PropertyListenerProc, (__bridge void *)self);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
}

// Init Audio Queue step4: config config queue with file's properties.
- (void) configQueueForLocal
{
    // magic data
    UInt32 size;
    _err = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyMagicCookieData, &size, NULL);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    else if (size > 0)
    {
        //char* cookies = new char[size];
        char* cookies = (char *)malloc(size);
        _err = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMagicCookieData, &size, &cookies);
        if (_err)
        {
            free(cookies);
            [self failWithErrorReason:DefaultErrorReason];
        }
        _err = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, cookies, size);
        if (_err)
        {
            free(cookies);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        free(cookies);
    }
    
    // channel layout
    _err = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyChannelLayout, &size, NULL);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    else if (size > 0)
    {
        AudioChannelLayout *acl = (AudioChannelLayout *)malloc(size);
        _err = AudioFileGetProperty(_audioFileID, kAudioFilePropertyChannelLayout, &size, &acl);
        if (_err)
        {
            free(acl);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        _err = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_ChannelLayout, acl, size);
        if (_err)
        {
            free(acl);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        free(acl);
    }
}

- (void) configQueueForStream
{
    UInt32 size;
    
    _err = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &size, NULL);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    else if (size > 0)
    {
        char* cookies = (char *)malloc(size);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &size, &cookies);
        if (_err)
        {
            free(cookies);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        _err = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, cookies, size);
        if (_err)
        {
            free(cookies);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        free(cookies);
    }
    
    _err = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_ChannelLayout, &size, NULL);
    if (_err)
    {
        [self failWithErrorReason:DefaultErrorReason];
        return;
    }
    else if (size > 0)
    {
        AudioChannelLayout* acl = (AudioChannelLayout *)malloc(size);
        _err = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_ChannelLayout, &size, &acl);
        if (_err)
        {
            free(acl);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        _err = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_ChannelLayout, acl, size);
        if (_err)
        {
            free(acl);
            [self failWithErrorReason:DefaultErrorReason];
            return;
        }
        free(acl);
    }
}

// Init Audio Queue step5: alloc queue buffers.
- (void) allocBuffers
{
    _isVBR = (_asbd.mBytesPerPacket == 0 || _asbd.mFramesPerPacket == 0);
    //UInt32 nPacket = _numPacketToRead;
    //UInt32 numBytes;
    
    for (int i = 0; i < kNumOfBuffers; i++) 
    {
        AudioQueueAllocateBufferWithPacketDescriptions(_audioQueue, _bufferByteSize, _isVBR ? _numPacketToRead : 0, &_audioQueueBuffers[i]);
        
        /*
        // set user data for testing
        _audioQueueBuffers[i]->mUserData = (void *)i;
        
        // fill buffers with data, enqueue them to queue
        
        AudioFileReadPackets(_audioFileID, false, &numBytes, _audioQueueBuffers[i]->mPacketDescriptions, _currentPacket, &nPacket, _audioQueueBuffers[i]->mAudioData);
        
        if (nPacket > 0) 
        {
            _audioQueueBuffers[i]->mAudioDataByteSize = numBytes;
            _audioQueueBuffers[i]->mPacketDescriptionCount = nPacket;
            //AudioQueueEnqueueBuffer(inAQ, inBuffer, THIS->mNumPacketToRead, inBuffer->mPacketDescriptions);
            
            AudioQueueEnqueueBuffer(_audioQueue, _audioQueueBuffers[i], _isVBR ? _numPacketToRead : 0, _isVBR ? _audioQueueBuffers[i]->mPacketDescriptions : NULL);
            
            _currentPacket += nPacket;
            //mCurrentTime += (mEstimatedDuration * nPacket / mNumOfPackets);
            //nPacket = mNumPacketToRead;
        }
         */
    }
}


@end
