//
//  AudioStreamBuffer.h
//  AudioPlayer
//
//  Created by wenguang pan on 11/29/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

@interface AudioStreamBuffer : NSObject
{
    UInt32 _numBytes;
    const void * _audioData;
    UInt32 _numPackets;
    AudioStreamPacketDescription * _packetDescs;
}

@property (nonatomic, assign) UInt32 numbytes;
@property (nonatomic) const void * audioData;
@property (nonatomic, assign) UInt32 numPackets;
@property (nonatomic) AudioStreamPacketDescription * packetDescs;

- (id)initWithNumBytes:(UInt32)byteCount audioData:(const void *)data numPackets:(UInt32)packetCount packetDescs:(AudioStreamPacketDescription *)packets;

@end
