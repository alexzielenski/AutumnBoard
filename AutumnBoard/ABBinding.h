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
typedef void *IconResourceRef;

typedef NS_ENUM(NSUInteger, ABBindingClass) {
    ABBindingClassFileInfo  = 1,
    ABBindingClassBundle    = 2,
    // Skipped?
    ABBindingClassCustom    = 4,
    ABBindingClassLink      = 5,
    ABBindingClassVariant   = 6,
    ABBindingClassComposite = 7,
    // Skipped?
    ABBindingClassVolume    = 9,
    ABBindingClassUTI       = 10,
    ABBindingClassSideFault = 11
};

void *ABPairBindingsWithURL(void *destination, NSURL *url);
NSString *ABStringFromOSType(OSType type);

CFStringRef ABBindingCopyUTI(ABBindingRef arg0);

ABBindingClass ABBindingGetBindingClass(ABBindingRef binding);
bool ABBindingIsSidebarVariant(ABBindingRef binding);
void ABBindingOverride(ABBindingRef destination, ABBindingRef custom);

NSString *ABBindingCopyDescription(ABBindingRef binding);
CFURLRef ABBindingGetURL(ABBindingRef binding);
UInt32 ABBindingGetOSType(ABBindingRef binding);
IconRef ABBindingGetIconRef(ABBindingRef binding);
void ABBindingSetIconRef(ABBindingRef binding, IconRef icon);
UInt64 ABBindingGetBadge(ABBindingRef binding);
void ABBindingSetBadge(ABBindingRef binding, UInt64 badge);

CFURLRef ABLinkBindingGetURL(ABBindingRef binding);
CFURLRef ABBundleBindingGetURL(ABBindingRef binding);
CFStringRef ABFileInfoBindingGetExtension(ABBindingRef binding);
UInt64 ABFileInfoBindingGetFlags(ABBindingRef binding);
CFStringRef ABVolumeBindingGetBundleIdentifier(ABBindingRef binding);
CFStringRef ABVolumeBindingGetBundleIconResourceName(ABBindingRef binding);

ABBindingRef ABLinkBindingResolve(ABBindingRef binding);
ABBindingRef ABVariantBindingGetBinding(ABBindingRef binding);
ABBindingRef ABCompositeBindingGetForegroundBinding(ABBindingRef binding);
ABBindingRef ABCompositeBindingGetBackgroundBinding(ABBindingRef binding);

CFURLRef ABIconResourceGetURL(IconResourceRef resource);
void ABIconResourceSetURL(IconResourceRef resource, CFURLRef url);
UInt64 ABIconResourceGetFlags(IconResourceRef resource);
void ABIconResourceSetFlags(IconResourceRef resource, UInt64 flags);

#endif /* defined(__AutumnBoard__ABBinding__) */
