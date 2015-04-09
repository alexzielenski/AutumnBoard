//
//  AutumnBoard.m
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/1/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Opee/Opee.h>
#import "ABLogging.h"
#import "SUStandardVersionComparator.h"

@interface NSImage (Private)
- (void)_drawMappingAlignmentRectToRect:(struct CGRect)arg1 withState:(unsigned long long)arg2 backgroundStyle:(int)arg3 operation:(unsigned long long)arg4 fraction:(double)arg5 flip:(BOOL)arg6 hints:(id)arg7;
@end

// NAMESPACING!
ZKSwizzleInterface($_ZABSidebarImage, NSSidebarImage, NSImage)
@implementation $_ZABSidebarImage

/* Disable Finder Sidebar's Masking of the images. Probably don't want to do this since SideBar images are gray anyway
 but we want any images we replace to be unmasked 
 
 !TODO: Make this a preference
 */
- (void)_drawMappingAlignmentRectToRect:(struct CGRect)arg1 withState:(unsigned long long)arg2 backgroundStyle:(int)arg3 operation:(unsigned long long)arg4 fraction:(double)arg5 flip:(BOOL)arg6 hints:(id)arg7 {
    [super _drawMappingAlignmentRectToRect:arg1
                                 withState:0x0
                           backgroundStyle:arg3
                                 operation:arg4
                                  fraction:arg5
                                      flip:arg6
                                     hints:arg7];
}
@end


#pragma mark - Initialize
OPInitialize {
    ABLog("AutumnBoard Loaded");    
}

#pragma mark - Support

NSString *ABLaunchServicesVersion() {
    static NSString * version = @"";
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *lsBundle = [NSBundle bundleWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework"];
        if (!lsBundle)
            version = @"0";
        else {
            NSDictionary *info = lsBundle.infoDictionary;
            version = info[(__bridge NSString *)kCFBundleVersionKey] ?: @"0";
        }
    });
    
    return version;
}

BOOL ABLaunchServicesVersionInRange(NSString *lower, NSString *upper) {
    NSString *ls = ABLaunchServicesVersion();
    NSComparisonResult lowerResult = [[SUStandardVersionComparator defaultComparator] compareVersion:lower toVersion:ls];
    NSComparisonResult upperResult = [[SUStandardVersionComparator defaultComparator] compareVersion:upper toVersion:ls];
    return lowerResult != NSOrderedDescending && upperResult != NSOrderedAscending;
}

BOOL ABLaunchServicesVersionEquals(NSString *version) {
    NSString *ls = ABLaunchServicesVersion();
    NSComparisonResult result = [[SUStandardVersionComparator defaultComparator] compareVersion:version toVersion:ls];
    return result == NSOrderedSame;
}

BOOL ABIsSupportedVersion() {
    static BOOL supported = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supported = ABLaunchServicesVersionInRange(ABLaunchServicesVersion101002, ABLaunchServicesVersion101003);
    });
    return supported;
}

BOOL ABIsInQuickLook() {
    NSString *name = [[NSProcessInfo processInfo] processName];
    return [name isEqualToString:@"quicklookd"] || [name isEqualToString:@"QuickLookSatellite"];
}
