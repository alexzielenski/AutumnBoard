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
        if (argc <= 1 || argc > 3) {
            printf("Usage: uti <extension> or uti -e <uti>\n");
            return 1;
        } else if (argc == 2) {
            NSString *uti = (__bridge_transfer NSString *)(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(@(argv[1])), NULL));
            printf("%s\n", uti.UTF8String);
        } else if (argc == 3) {
            CFStringRef class = NULL;
            if (strcmp(argv[1], "-e") == 0) {
                class = kUTTagClassFilenameExtension;
            } else if (strcmp(argv[1], "-o") == 0) {
                class = kUTTagClassOSType;
            } else if (strcmp(argv[1], "-m") == 0) {
                class = kUTTagClassMIMEType;
            } else {
                class = kUTTagClassFilenameExtension;
            }
            
            NSArray *types = (__bridge_transfer NSArray *)UTTypeCopyAllTagsWithClass((__bridge CFStringRef)@(argv[2]), class);
            printf("%s\n", types.description.UTF8String);
        }
    }
    return 0;
}

