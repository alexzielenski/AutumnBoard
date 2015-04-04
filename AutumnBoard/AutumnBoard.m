//
//  AutumnBoard.m
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/1/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Opee/Opee.h>

#import "ABBinding.h"
#import "ABResourceThemer.h"


@interface NSImage (Private)
- (void)_drawMappingAlignmentRectToRect:(struct CGRect)arg1 withState:(unsigned long long)arg2 backgroundStyle:(int)arg3 operation:(unsigned long long)arg4 fraction:(double)arg5 flip:(BOOL)arg6 hints:(id)arg7;
@end

ZKSwizzleInterface(ABImage, NSSidebarImage, NSImage)
@implementation ABImage

- (void)_drawMappingAlignmentRectToRect:(struct CGRect)arg1 withState:(unsigned long long)arg2 backgroundStyle:(int)arg3 operation:(unsigned long long)arg4 fraction:(double)arg5 flip:(BOOL)arg6 hints:(id)arg7 {
    [super _drawMappingAlignmentRectToRect:arg1
                                 withState:0x0
                           backgroundStyle:arg3
                                 operation:arg4
                                  fraction:arg5
                                      flip:arg6
                                     hints:arg7];
}
@end

#pragma mark - Initialize
OPInitialize {
    ABLog("AutumnBoard Loaded");
}
