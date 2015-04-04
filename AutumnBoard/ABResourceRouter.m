//
//  ABResourceRouter.c
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import "ABResourceRouter.h"
#import <Opee/Opee.h>
#import "ABLogging.h"
#import "ABResourceThemer.h"
#import <mach-o/dyld.h>

#pragma mark URL Rerouting

OPHook4(CFURLRef, CFBundleCopyResourceURL, CFBundleRef, bundle, CFStringRef, resourceName, CFStringRef, resourceType, CFStringRef, subDirName) {
    CFURLRef finalURL = NULL;
    
    if ([((__bridge NSString *)resourceName).pathExtension isEqualToString:@"icns"] ||
        [((__bridge NSString *)resourceType) isEqualToString:@"icns"]) {
        ABLog("Bundle: %@, %@, %@", bundle, resourceName, resourceType);
    }
    
    // for some reason when I __bridge over cfbundle shit breaks
    NSBundle *nsBundle = [NSBundle bundleWithPath:((__bridge_transfer NSURL *)CFBundleCopyBundleURL(bundle)).path];
    if (!hasResourceForBundle(nsBundle, resourceName, resourceType, subDirName, &finalURL)) {
        finalURL = OPOldCall(bundle, resourceName, resourceType, subDirName);
    }
    
    return finalURL;
}

OPHook4(CFURLRef, CFBundleCopyResourceURLInDirectory, CFURLRef, bundleURL, CFStringRef, resourceName, CFStringRef, resourceType, CFStringRef, subDirName) {
    CFURLRef finalURL = NULL;
    
    if (bundleURL) {
        NSBundle *nsBundle = [NSBundle bundleWithURL:(__bridge NSURL *)bundleURL];
        if (!hasResourceForBundle(nsBundle, resourceName, resourceType, subDirName, &finalURL)) {
            finalURL = OPOldCall(bundleURL, resourceName, resourceType, subDirName);
        }
    }
    
    if ([((__bridge NSString *)resourceName).pathExtension isEqualToString:@"icns"] ||
        [((__bridge NSString *)resourceType) isEqualToString:@"icns"]) {
        ABLog("Directory: %@, %@, %@ (%@)", bundleURL, resourceName, resourceType, finalURL);
    }
        
    return finalURL;
}

#pragma mark - Shit that's probably unnecessary

OPHook1(CGDataProviderRef, CGDataProviderCreateWithFilename, const char *, filename) {
    NSURL *url = [NSURL fileURLWithPath:@(filename)];
    if ((url = replacementURLForURL(url))) {
        return OPOldCall(url.path.UTF8String);
    }
    
    return OPOldCall(filename);
}

OPHook1(CGDataProviderRef, CGDataProviderCreateWithURL, CFURLRef, url) {
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(url);
}

OPHook4(CFDataRef, CFURLCreateData, CFAllocatorRef, allocator, CFURLRef, url, CFStringEncoding, encoding, Boolean, escapeWhitespace) {
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(allocator, url, encoding, escapeWhitespace);
}

OPHook2(CGImageSourceRef, CGImageSourceCreateWithURL, CFURLRef, url, CFDictionaryRef, options) {
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(url, options);
}

OPInitialize {
    OPHookFunction(CFBundleCopyResourceURLInDirectory);
    OPHookFunction(CFBundleCopyResourceURL);
    
    // Quicklook should always return the original image
    //!TODO: Expand this list to photoshop/acorn/preview/pixelmator/sketch
    //! basically anything that has its UTI Role set to editor (viewer?) for the given file
    //! but only for the safety methods CFURLCreateData, CGDataProviderCreateWith(URL/FIlename), CGImageSourceCreatewithURL

    if (ABIsInQuicklook()) {
        return;
    }

    
    //    OPHookFunction(__UTTypeCopyIconFileName);
    OPHookFunction(CGImageSourceCreateWithURL);
    OPHookFunction(CGDataProviderCreateWithFilename);
    OPHookFunction(CGDataProviderCreateWithURL);
    OPHookFunction(CFURLCreateData);
}
