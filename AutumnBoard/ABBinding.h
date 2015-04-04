//
//  ABBinding.h
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#ifndef __AutumnBoard__ABBinding__
#define __AutumnBoard__ABBinding__

#import "ABLogging.h"
#import <Foundation/Foundation.h>

typedef void *ABBindingRef;

void *ABPairBindingsWithURL(void *destination, void *custom, NSURL *url);
void *ABPairBindings(void *destination, void *custom);
NSString *ABStringFromOSType(OSType type);

#endif /* defined(__AutumnBoard__ABBinding__) */
