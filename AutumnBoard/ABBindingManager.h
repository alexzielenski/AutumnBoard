//
//  ABBindingManager.h
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#ifndef __AutumnBoard__ABBindingManager__
#define __AutumnBoard__ABBindingManager__

#import <CoreFoundation/CoreFoundation.h>
void *(*CreateWithResourceURL)(CFURLRef url, BOOL arg1);
static void *(*CreateWithURL)(CFURLRef url, BOOL arg1);

#endif /* defined(__AutumnBoard__ABBindingManager__) */
