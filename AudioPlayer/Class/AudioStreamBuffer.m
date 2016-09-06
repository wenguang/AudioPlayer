//
//  AudioStreamBuffer.m
//  AudioPlayer
//
//  Created by wenguang pan on 11/29/13.
//  Copyright (c) 2013 wenguang. All rights reserved.
//

#import "AudioStreamBuffer.h"

@implementation AudioStreamBuffer

@synthesize numbytes;
@synthesize audioData;
@synthesize numPackets;
@synthesize packetDescs;

- (id)initWithNumBytes:(UInt32)byteCount audioData:(const void *)data numPackets:(UInt32)packetCount packetDescs:(AudioStreamPacketDescription *)packets
{
    if (self = [super init])
    {
        _numBytes = byteCount;
        _audioData = data;
        _numPackets = packetCount;
        _packetDescs = packets;
    }
    return self;
}

@end
