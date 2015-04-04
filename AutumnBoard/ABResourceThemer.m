//
//  ABResourceThemer.c
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import "ABResourceThemer.h"
#import <Opee/Opee.h>

static NSURL *ThemePath;
static NSString *nameOfIconForBundle(NSBundle *bundle);
static NSURL *URLForBundle(NSBundle *bundle);
static NSURL *URLForOSType(NSString *type);
static NSURL *URLForUTIFile(NSString *name);

OPInitialize {
    ThemePath = [NSURL fileURLWithPath:@"/Library/AutumnBoard/Themes/Fladder2"];
}

#pragma mark - URL Generation

static NSURL *URLForBundle(NSBundle *bundle) {
    if (!bundle || ![bundle isKindOfClass:[NSBundle class]])
        return nil;
    
    NSDictionary *info = [bundle infoDictionary];
    if (!info)
        return nil;
    
    NSString *identifier = info[(__bridge NSString *)kCFBundleIdentifierKey];
    
    if (!identifier) {
        return nil;
    }
    return [[ThemePath URLByAppendingPathComponent:@"Bundles"] URLByAppendingPathComponent:identifier];
}


NSURL *URLForOSType(NSString *type) {
    return [[[ThemePath URLByAppendingPathComponent:@"OSTypes"] URLByAppendingPathComponent:type] URLByAppendingPathExtension:@"icns"];
}

NSURL *URLForUTIFile(NSString *name) {
    return [[[ThemePath URLByAppendingPathComponent:@"UTIs"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

#pragma mark - Bundle Helpers

static NSString *nameOfIconForBundle(NSBundle *bundle) {
    NSDictionary *info = [bundle infoDictionary];
    if (!info)
        return nil;
    
    NSString *iconName = info[@"CFBundleIconFile"];
    if (iconName)
        return iconName;
    
    iconName = info[@"NSPrefPaneIconFile"];
    return iconName;
}

NSURL *iconForBundle(NSBundle *bundle) {
    // Shortcut so you dont have to make a folder for each app to change its icon
    NSURL *bndlURL = [URLForBundle(bundle) URLByAppendingPathExtension:@"icns"];
    if (bndlURL && [[NSFileManager defaultManager] fileExistsAtPath:bndlURL.path]) {
        return bndlURL;
    }
    
    NSString *iconName = nameOfIconForBundle(bundle);
    // This bundle has no icon, return our generic one
    if (!iconName || iconName.length == 0) {
        //!TODO: Even if there is an icon name, check to see if it exists
        if (bundle.infoDictionary.count && bundle.bundlePath.pathExtension.length)
            return customIconForExtension(bundle.bundlePath.pathExtension);
        return nil;
    }
    
    return ([bundle URLForResource:iconName.stringByDeletingPathExtension withExtension:@"icns"]);
}

BOOL hasResourceForBundle(NSBundle *bundle, CFStringRef resource, CFStringRef resourceType, CFStringRef subDir, CFURLRef *resourceURL) {
    NSURL *finalURL = URLForBundle(bundle);
    if (!finalURL)
        return NO;
    if (!resource)
        return NO;
    
    if (subDir != NULL && CFStringGetLength(subDir) > 0) {
        finalURL = [finalURL URLByAppendingPathComponent:(__bridge NSString *)(subDir)];
    }
    
    // If the extensions is on resource, move it to resourceType
    if (resourceType == NULL && ((__bridge NSString *)resource).pathExtension != nil) {
        resourceType = (__bridge CFStringRef)((__bridge NSString *)resource).pathExtension;
        resource = (__bridge CFStringRef)((__bridge NSString *)resource).stringByDeletingPathExtension;
    }
    
    // Add support for the shorthand of calling the icon by the bundleidentifier.icns
    NSString *iconName = nameOfIconForBundle(bundle);
    if ([iconName isEqualToString:(__bridge NSString *)(resource)] ||
        [iconName isEqualToString:[(__bridge NSString *)resource stringByAppendingPathExtension:(__bridge NSString *)resourceType]]) {
        
        NSURL *iconURL = [URLForBundle(bundle) URLByAppendingPathExtension:@"icns"];
        if (iconURL && [[NSFileManager defaultManager] fileExistsAtPath:iconURL.path]) {
            *resourceURL = (__bridge_retained CFURLRef)iconURL;
            return YES;
        }
    }
    
    if (resourceType != NULL && resource != NULL &&
        CFStringGetLength(resourceType) > 0 &&
        CFStringGetLength(resource) > 0) {
        // we know exactly what file we are looking for
        finalURL = [finalURL URLByAppendingPathComponent:(__bridge NSString *)(resource)];
        finalURL = [finalURL URLByAppendingPathExtension:(__bridge NSString *)resourceType];
    } else {
        // Search all files for something that matches this name
        NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:finalURL
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsPackageDescendants
                                                                                error:nil];
        if (!fileNames.count)
            return NO;
        
        BOOL winning = NO;
        for (NSURL *url in fileNames) {
            NSString *name = url.lastPathComponent;
            // case-sensitive?
            if ([name.stringByDeletingPathExtension isEqualToString:(__bridge NSString *)(resource)] ||
                [name isEqualToString:(__bridge NSString *)(resource)]) {
                winning = YES;
                finalURL = url;
                break;
            }
        }
        
        if (!winning)
            return NO;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:finalURL.path]) {
        return NO;
    }
    
    *resourceURL = (__bridge_retained CFURLRef)(finalURL);
    return YES;
}

NSURL *replacementURLForURL(NSURL *url) {
    if (!url)
        return nil;
    
    // Step 1, check absolute paths
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *testURL = customIconForURL(url);
    if (testURL)
        return testURL;
    
    // Step 2, traverse down path until we get a bundle with an identifier
    BOOL foundBundle = NO;
    NSBundle *bndl = nil;
    testURL = [url URLByDeletingLastPathComponent];
    NSUInteger cnt = 0;
    
    //!TODO: Check instead for last occurrance of Contents/Resources
    while (![testURL.path isEqualToString:@"/.."] && !foundBundle && cnt++ <= 10) {
        bndl = [NSBundle bundleWithURL:testURL];
        if (bndl.bundleIdentifier) {
            foundBundle = YES;
            break;
        }
        
        testURL = [testURL URLByDeletingLastPathComponent];
    }
    
    NSArray *pathComponents = url.pathComponents;
    if (foundBundle && [pathComponents containsObject:@"Resources"]) {
        NSUInteger rsrcIdx = [pathComponents indexOfObject:@"Resources"];
        testURL = URLForBundle(bndl);
        
        for (NSUInteger x =  rsrcIdx + 1; x < pathComponents.count; x++) {
            testURL = [testURL URLByAppendingPathComponent:[pathComponents[x] copy]];
        }
        if ([manager fileExistsAtPath:testURL.path]) {
            return testURL;
        }
    }
    
    return nil;
}

NSURL *customIconForURL(NSURL *url) {
    if (!url)
        return nil;
    
    // Step 1, check if our theme structure has a custom icon for this hardcoded
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSURL *testURL = [[ThemePath URLByAppendingPathComponent:url.path] URLByAppendingPathExtension:@"icns"];
    if ([manager fileExistsAtPath:testURL.path isDirectory:&isDir] && !isDir) {
        return testURL;
    }
    

    return nil;
}

#pragma mark - UTI Helpers

NSURL *customIconForOSType(NSString *type) {
    if (!type || type.length != 4 || [type isEqualToString:@"????"]) {
        return nil;
    }
    
    // step 1, check if we have the actual type.icns
    NSURL *tentativeURL = URLForOSType(type);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2, convert to uti and go ham
    // step 2: get all of the utis for this extension and check against that
    NSArray *utis = (__bridge_transfer NSArray *)UTTypeCreateAllIdentifiersForTag(kUTTagClassOSType, (__bridge CFStringRef)type, NULL);
    for (NSString *uti in utis) {
        // Use this so it also checks other variants of this extension
        // such as jpeg vs jpg in addition to public.jpeg
        tentativeURL = customIconForUTI(uti);
        if (tentativeURL)
            return tentativeURL;
    }
    
    return nil;
}

NSURL *customIconForUTI(NSString *uti) {
    if (!uti || UTTypeIsDynamic((__bridge CFStringRef)(uti)))
        return nil;
    
    // step 1, check if we have the actual uti.icns
    NSURL *tentativeURL = URLForUTIFile(uti);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2: get all of the extensions for this uti and check against that
    NSArray *extensions = (__bridge_transfer NSArray *)(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)(uti), kUTTagClassFilenameExtension));
    for (NSString *extension in extensions) {
        tentativeURL = URLForUTIFile(extension);
        if ([manager fileExistsAtPath: tentativeURL.path]) {
            return tentativeURL;
        }
    }
    
    // step 3: get all of the ostypes for this uti and check that too
    NSArray *ostypes = (__bridge_transfer NSArray *)UTTypeCopyAllTagsWithClass((__bridge CFStringRef)(uti), kUTTagClassOSType);
    for (NSString *ostype in ostypes) {
        tentativeURL = URLForOSType(ostype);
        if ([manager fileExistsAtPath:tentativeURL.path]) {
            return tentativeURL;
        }
    }
    
    return nil;
}

NSURL *customIconForExtension(NSString *extension) {
    if (!extension)
        return nil;
    
    // step 1, check if we have the actual extension.icns
    NSURL *tentativeURL = URLForUTIFile(extension);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2: get all of the utis for this extension and check against that
    NSArray *utis = (__bridge_transfer NSArray *)UTTypeCreateAllIdentifiersForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    for (NSString *uti in utis) {
        // Use this so it also checks other variants of this extension
        // such as jpeg vs jpg in addition to public.jpeg
        tentativeURL = customIconForUTI(uti);
        if (tentativeURL)
            return tentativeURL;
    }
    
    return nil;
}

BOOL ABIsInQuicklook() {
    NSString *name = [[NSProcessInfo processInfo] processName];
    return [name isEqualToString:@"quicklookd"] || [name isEqualToString:@"QuickLookSatellite"];
}
