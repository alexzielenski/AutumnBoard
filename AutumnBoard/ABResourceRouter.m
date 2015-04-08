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

static CFStringRef (*__UTTypeCopyIconFileName)(CFStringRef uti, CFStringRef conformingToType, CFURLRef *baseURL, BOOL *success);
OPHook4(CFStringRef, __UTTypeCopyIconFileName, CFStringRef, uti, CFStringRef, conformingToType, CFURLRef *, baseURL, BOOL *, success) {
    NSURL *replacement = customIconForUTI((__bridge NSString *)uti);
    if (replacement) {
        if (success)
            *success = YES;
        if (baseURL)
            *baseURL = (__bridge_retained CFURLRef)(replacement.URLByDeletingLastPathComponent);
        return (__bridge_retained CFStringRef)replacement.lastPathComponent;
    }
    
    return OPOldCall(uti, conformingToType, baseURL, success);
}

OPInitialize {
    __UTTypeCopyIconFileName = OPFindSymbol(NULL, "__UTTypeCopyIconFileName");
    OPHookFunction(__UTTypeCopyIconFileName);
//    CFBundleCopyFindResources = OPFindSymbol(NULL, "__CFBundleCopyFindResources");
    OPHookFunctionPtr(_CFBundleCopyFindResources, $_CFBundleCopyFindResources, (void **)&O__CFBundleCopyFindResources);
}
