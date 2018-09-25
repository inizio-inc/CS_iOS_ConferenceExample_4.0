/*
 * Copyright © 2016 Intel Corporation. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>
#import "FileVideoFrameGenerator.h"

#include <stdio.h>

@implementation FileVideoFrameGenerator{
  CGSize _resolution;
  NSInteger _frameRate;
  NSInteger _frameSize;
  FILE* _fd;
}

-(instancetype)initWithPath:(NSString *)path resolution:(CGSize)resolution frameRate:(NSInteger)frameRate{
  self = [super init];
  _resolution=resolution;
  _frameRate=frameRate;
  NSInteger size=resolution.width*resolution.height;
  _frameSize=size+size/2;
  _fd=fopen([path UTF8String], "rb");
  if(!_fd){
    NSLog(@"Open file for video frame generator failed.");
  }
  return self;
}

-(NSUInteger)frameRate{
  return _frameRate;
}

-(CGSize)resolution{
  return _resolution;
}

-(NSUInteger)nextFrame:(uint8_t*)buffer capacity:(const NSUInteger)capacity{
  if(capacity<_frameSize){
    NSAssert(false, @"No enough space for next frame.");
    return 0;
  }
  if(fread(buffer, 1, _frameSize, _fd)!=_frameSize){
    fseek(_fd,0,SEEK_SET);
    NSLog(@"Rewind");
    fread(buffer, 1, _frameSize, _fd);
  }
  return _frameSize;
}

-(void)dealloc{
  fclose(_fd);
}

@end