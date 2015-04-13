//
//  main.m
//  uti
//
//  Created by Alexander Zielenski on 4/13/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *uti = (__bridge_transfer NSString *)(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(@(argv[1])), NULL));
        printf("%s\n", uti.UTF8String);
    }
    return 0;
}

