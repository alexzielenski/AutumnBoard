//
//  main.m
//  bndl
//
//  Created by Alexander Zielenski on 4/13/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NSString *bundleIdentifierForAppName(NSString *appName) {
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSString * appPath = [workspace fullPathForApplication:appName];
    if (appPath) {
        NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
        return [appBundle bundleIdentifier];
    }
    return nil;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc == 1) {
            printf("You must specify a bundle name!\n");
            return 1;
        } else if (argc == 2) {
            // try to get the bundle at path
            NSBundle *bndl = [NSBundle bundleWithPath:@(argv[1])];
            if (bndl && bndl.bundleIdentifier) {
                printf("%s\n", bndl.bundleIdentifier.UTF8String);
                return 0;
            }

        }
        // insert code here...
        NSMutableArray *components = [NSMutableArray array];
        for (int c = 1; c < argc; c++) {
            [components addObject:@(argv[c])];
        }
        
        NSString *name = [components componentsJoinedByString:@" "];
        printf("%s\n", bundleIdentifierForAppName(name).UTF8String);
    }
    return 0;
}
