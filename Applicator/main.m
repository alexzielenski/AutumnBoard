//
//  main.m
//  Applicator
//
//  Created by Alexander Zielenski on 4/13/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        NSMutableArray *themeStorage = [NSMutableArray array];
        for (int x = 1; x < argc; x++) {
            [themeStorage addObject:@(argv[x])];
        }
        
        if (themeStorage.count == 0) {
            printf("You must specify themes to be applied!\n");
            return 1;
        }
        
        NSURL *baseURL = [NSURL fileURLWithPath:@"/Library/AutumnBoard/Themes"];
        NSURL *destURL = [NSURL fileURLWithPath:@"/Library/AutumnBoard/ComputedTheme"];
        NSFileManager *manager = [NSFileManager defaultManager];
        
        [manager removeItemAtURL:destURL error:nil];
        [manager createDirectoryAtURL:destURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        
        for (NSInteger idx = themeStorage.count - 1; idx >= 0; idx--) {
            NSString *theme = themeStorage[idx];
            NSURL *themeURL = [NSURL URLWithString:theme relativeToURL:baseURL];
            NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:themeURL
          includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                             options:NSDirectoryEnumerationSkipsHiddenFiles
                        errorHandler:^BOOL(NSURL *url, NSError *error) {
                            return YES;
                        }];
            for (NSURL *url in enumerator) {
                NSString *path = [url.path substringFromIndex:themeURL.path.length];
                NSURL *abs = [destURL URLByAppendingPathComponent:path];
                NSDictionary *props = [url resourceValuesForKeys:@[ NSURLIsDirectoryKey ] error:nil];
                if (![props[NSURLIsDirectoryKey] boolValue]) {
//                    [NSURL writeBookmarkData:[url bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
//                                           includingResourceValuesForKeys:@[]
//                                                            relativeToURL:nil
//                                                                    error:nil]
//                                       toURL:abs
//                                     options:NSURLBookmarkCreationSuitableForBookmarkFile
//                                       error:nil];
                    [manager removeItemAtURL:url error:nil];
                    [manager createSymbolicLinkAtURL:abs.absoluteURL withDestinationURL:url.absoluteURL error:nil];
                } else {
                    [manager createDirectoryAtURL:abs
                      withIntermediateDirectories:YES
                                       attributes:nil
                                            error:nil];
                }
            }
        }
        
        printf("Done.\n");
    }
    
    return 0;
}
