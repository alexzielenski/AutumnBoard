//
//  main.m
//  TestEnvironment
//
//  Created by Alexander Zielenski on 4/13/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ABLogging.h"
#import "ABResourceThemer.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Hello, World!");
        NSLog(@"%@", customIconForURL([NSURL fileURLWithPath:@"/Applications/Adobe Photoshop CC 2014"]));
    }
    return 0;
}
