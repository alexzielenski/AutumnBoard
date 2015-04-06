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

CFTypeRef _CFBundleCopyFindResources(CFBundleRef bundle, CFURLRef bundleURL, CFArrayRef languages, CFStringRef resourceName, CFStringRef resourceType, CFStringRef subPath, CFStringRef lproj, Boolean returnArray, Boolean localized, Boolean (^predicate)(CFStringRef filename, Boolean *stop));
CFTypeRef (*O__CFBundleCopyFindResources)(CFBundleRef bundle, CFURLRef bundleURL, CFArrayRef languages, CFStringRef resourceName, CFStringRef resourceType, CFStringRef subPath, CFStringRef lproj, Boolean returnArray, Boolean localized, Boolean (^predicate)(CFStringRef filename, Boolean *stop));

CFTypeRef $_CFBundleCopyFindResources(CFBundleRef bundle, CFURLRef bundleURL, CFArrayRef languages, CFStringRef resourceName, CFStringRef resourceType, CFStringRef subPath, CFStringRef lproj, Boolean returnArray, Boolean localized, Boolean (^predicate)(CFStringRef filename, Boolean *stop)) {
    CFTypeRef rtn = O__CFBundleCopyFindResources(bundle, bundleURL, languages, resourceName, resourceType, subPath, lproj, returnArray, localized, predicate);
    
    if (!bundle) {
        return rtn;
    }
    NSBundle *nsBundle = [NSBundle bundleWithPath:((__bridge_transfer NSURL *)CFBundleCopyBundleURL(bundle)).path];
    if (returnArray) {

        CFArrayRef array = (CFArrayRef)rtn;
        NSMutableArray *ar = [NSMutableArray arrayWithCapacity:CFArrayGetCount(array)];
        for (CFIndex idx = 0; idx < CFArrayGetCount(array); idx++) {
            CFURLRef url = CFArrayGetValueAtIndex(array, idx);
            NSURL *replacement = replacementURLForURLRelativeToBundle((__bridge NSURL*)url, nsBundle);
            
            if (replacement) {
                [ar addObject:replacement];
            } else {
                [ar addObject:(__bridge NSURL *)url];
            }
        }
        
        CFRelease(array);
        return (__bridge_retained CFArrayRef)ar;
    } else {
        CFURLRef url = (CFURLRef)rtn;
        CFURLRef replacement = (__bridge_retained CFURLRef)replacementURLForURLRelativeToBundle((__bridge NSURL*)url, nsBundle);
        
        if (replacement) {
            CFRelease(url);
            return replacement;
        }
        
        return url;
    }
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

void (*CGImageReadCreateWithURL)(CFURLRef arg0, int arg1, int arg2);
OPHook3(void *, CGImageReadCreateWithURL, CFURLRef, url, int, arg1, int, arg2) {
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    
    return OPOldCall(url, arg1, arg2);
}

OPInitialize {
//    CFBundleCopyFindResources = OPFindSymbol(NULL, "__CFBundleCopyFindResources");
//    OPHookFunction(CFBundleCopyResourceURLInDirectory);
//    OPHookFunction(CFBundleCopyResourceURL);
    OPHookFunctionPtr(_CFBundleCopyFindResources, $_CFBundleCopyFindResources, (void **)&O__CFBundleCopyFindResources);
    
    // Quicklook should always return the original image
    //!TODO: Expand this list to photoshop/acorn/preview/pixelmator/sketch
    //! basically anything that has its UTI Role set to editor (viewer?) for the given file
    //! but only for the safety methods CFURLCreateData, CGDataProviderCreateWith(URL/FIlename), CGImageSourceCreatewithURL

    if (ABIsInQuicklook()) {
        return;
    }

    CGImageReadCreateWithURL = OPFindSymbol(NULL, "_CGImageReadCreateWithURL");
    OPHookFunction(CGImageReadCreateWithURL);
    OPHookFunction(CGImageSourceCreateWithURL);
    OPHookFunction(CGDataProviderCreateWithFilename);
    OPHookFunction(CGDataProviderCreateWithURL);
    OPHookFunction(CFURLCreateData);
}
