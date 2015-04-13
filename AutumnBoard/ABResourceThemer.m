//
//  ABResourceThemer.c
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import "ABResourceThemer.h"
#import <Opee/Opee.h>
#import "ABLogging.h"

static NSURL *ThemePath;
static NSString *nameOfIconForBundle(NSBundle *bundle);
static NSURL *URLForBundle(NSBundle *bundle);
static NSURL *URLForOSType(NSString *type);
static NSURL *URLForUTIFile(NSString *name);
static NSDictionary *typeIndexForBundle(NSBundle *bundle);

static NSString *const ABTypeIndexUTIsKey       = @"utis";
static NSString *const ABTypeIndexExtensionsKey = @"extenions";
static NSString *const ABTypeIndexMIMEsKey      = @"mimes";
static NSString *const ABTypeIndexOSTypesKey    = @"ostypes";
static NSString *const ABTypeIndexRoleKey       = @"role";

OPInitialize {
    ThemePath = [NSURL fileURLWithPath:@"/Library/AutumnBoard/ComputedTheme"];
}

BOOL ABURLInThemesDirectory(NSURL *url) {
    return [url.path hasPrefix:ThemePath.path];
}

#pragma mark - URL Generation
static NSURL *resolve(NSURL *url) {
    if (!url)
        return nil;
    return [[NSURL URLByResolvingAliasFileAtURL:url options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting error:nil] URLByResolvingSymlinksInPath];
}

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

static NSURL *URLForOSType(NSString *type) {
    if (!type)
        return nil;
    
    return [[[ThemePath URLByAppendingPathComponent:@"OSTypes"] URLByAppendingPathComponent:type] URLByAppendingPathExtension:@"icns"];
}

static NSURL *URLForUTIFile(NSString *name) {
    if (!name)
        return nil;
    return [[[ThemePath URLByAppendingPathComponent:@"UTIs"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

static NSURL *URLForExtension(NSString *name) {
    if (!name)
        return nil;
    return [[[ThemePath URLByAppendingPathComponent:@"Extensions"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

static NSURL *URLForAbsolutePath(NSURL *path) {
    if (!path)
        return nil;
    
    NSString *name = [path.path stringByAbbreviatingWithTildeInPath];
    if (!name)
        return nil;
    
    NSURL *url = [[ThemePath URLByAppendingPathComponent:@"Absolutes"] URLByAppendingPathComponent:name];
    if (![url.pathExtension isEqualToString:@"icns"])
        url = [url URLByAppendingPathExtension:@"icns"];
    
    return url;
}

#pragma mark - Bundle Helpers
static NSDictionary *typeIndexForBundle(NSBundle *bundle) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    
    if (!bundle.bundleIdentifier)
        return nil;
    
    //!TODO: Don't organize the index by bundle identifier
    //! instead organize it by the absolute path to the icon
    //! that way we don't have to do shit like this
    NSString *identifier = bundle.bundleIdentifier;
    NSDictionary *cached = [cache objectForKey:identifier];
    if (cached)
        return cached;
    
    NSDictionary *info = bundle.infoDictionary;
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSDictionary *types = info[@"CFBundleDocumentTypes"];
    
    for (NSDictionary *type in types) {
        NSString *icon = type[@"CFBundleTypeIconFile"];
        if (!icon)
            continue;
        
        NSMutableDictionary *entry = (NSMutableDictionary *)index[icon];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            entry[ABTypeIndexUTIsKey]       = [NSMutableArray array];
            entry[ABTypeIndexExtensionsKey] = [NSMutableArray array];
//            entry[ABTypeIndexMIMEsKey]      = [NSMutableArray array];
            entry[ABTypeIndexOSTypesKey]    = [NSMutableArray array];

            index[icon] = entry;
        }
        NSString *icext = type[@"ICExtension"];
        NSArray *exts = type[@"CFBundleTypeExtensions"];
        if (!exts && icext)
            exts = @[icext];
        
        // We need to do this incase the app uses the same icon for different document types
        [(NSMutableArray *)entry[ABTypeIndexUTIsKey] addObjectsFromArray:type[@"LSItemContentTypes"]];
        [(NSMutableArray *)entry[ABTypeIndexExtensionsKey] addObjectsFromArray:exts];
//        [(NSMutableArray *)entry[ABTypeIndexMIMEsKey] addObjectsFromArray:type[@"CFBundleTypeMIMETypes"]];
        [(NSMutableArray *)entry[ABTypeIndexOSTypesKey] addObjectsFromArray:type[@"CFBundleTypeOSTypes"]];
    }
    
    types = info[@"UTExportedTypeDeclarations"];
    for (NSDictionary *type in types) {
        NSString *icon = type[@"UTTypeIconFile"];
        if (!icon)
            continue;
        
        NSMutableDictionary *entry = (NSMutableDictionary *)index[icon];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            entry[ABTypeIndexUTIsKey]       = [NSMutableArray array];
            entry[ABTypeIndexExtensionsKey] = [NSMutableArray array];
            //            entry[ABTypeIndexMIMEsKey]      = [NSMutableArray array];
            entry[ABTypeIndexOSTypesKey]    = [NSMutableArray array];
            
            index[icon] = entry;
        }
        
        NSString *uti = type[@"UTTypeIdentifier"];
        NSDictionary *spec = type[@"UTTypeTagSpecification"];
        id exts = spec[@"public.filename-extension"] ?: @[];
        id ostypes = spec[@"com.apple.ostype"] ?: @[];
        if (![exts isKindOfClass:[NSArray class]])
            exts = @[exts];
        if (![ostypes isKindOfClass:[NSArray class]])
            ostypes = @[ostypes];
        
        [(NSMutableArray *)entry[ABTypeIndexUTIsKey] addObject: uti];
        [(NSMutableArray *)entry[ABTypeIndexExtensionsKey] addObjectsFromArray:exts];
        [(NSMutableArray *)entry[ABTypeIndexOSTypesKey] addObjectsFromArray:ostypes];
    }
    
    cache[identifier] = index;
    return index;
}

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

static NSURL *_iconForBundle(NSBundle *bundle) {
    // Check Absolute Path
    NSURL *absolute = customIconForURL(bundle.bundleURL);
    if (absolute) {
        return absolute;
    }
    
    // Shortcut so you dont have to make a folder for each app to change its icon
    NSURL *bndlURL = [URLForBundle(bundle) URLByAppendingPathExtension:@"icns"];
    if (bndlURL && [[NSFileManager defaultManager] fileExistsAtPath:bndlURL.path]) {
        return bndlURL;
    }
    
    NSString *iconName = nameOfIconForBundle(bundle);
    if (!iconName)
        return nil;
    
    if (!iconName.pathExtension)
        iconName = [iconName stringByAppendingPathExtension:@"icns"];
    
    NSURL *iconURL = [bundle.resourceURL URLByAppendingPathComponent:iconName];
    return replacementURLForURLRelativeToBundle(iconURL, bundle);
}

NSURL *iconForBundle(NSBundle *bundle) {
    return resolve(_iconForBundle(bundle));
}

#pragma mark - Absolute Path Helpers
static NSURL *_replacementURLForURLRelativeToBundle(NSURL *url, NSBundle *bndl) {
    if (!url || !url.isFileURL || !bndl.bundleIdentifier || ABURLInThemesDirectory(url))
        return nil;
    
    // Step 1, check absolute paths
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *testURL = customIconForURL(url);
    if (testURL)
        return testURL;

    NSArray *urlComponents = [url.path substringFromIndex:bndl.bundlePath.length].pathComponents;
    //!TODO: get the last index of
    NSUInteger rsrcIdx = [urlComponents indexOfObject:@"Resources"];
    if (rsrcIdx == NSNotFound)
        return nil;
    
    // Add support for the shorthand of calling the icon by the bundleidentifier.icns
    NSString *iconName = nameOfIconForBundle(bndl);
    NSString *lastObject = urlComponents.lastObject;
    if ((([iconName.stringByDeletingPathExtension isEqualToString:lastObject.stringByDeletingPathExtension] &&
        [lastObject.pathExtension.lowercaseString isEqualToString:@"icns"]) ||
        [iconName isEqualToString:lastObject]) &&
        rsrcIdx == urlComponents.count - 2) {
        
        NSURL *iconURL = [URLForBundle(bndl) URLByAppendingPathExtension:@"icns"];
        if ([manager fileExistsAtPath:iconURL.path]) {
            return iconURL;
        }
    }
    
    testURL = URLForBundle(bndl);
    for (NSUInteger x =  rsrcIdx + 1; x < urlComponents.count; x++) {
        testURL = [testURL URLByAppendingPathComponent:urlComponents[x]];
    }
    
    if ([manager fileExistsAtPath:testURL.path])
        return testURL;
    
    
    // Search the bundle's declared types to see if the resource we are looking for
    // is actually an document icon
    if ([url.pathExtension.lowercaseString isEqualToString:@"icns"]) {
        NSBundle *indexBundle = bndl;
        if ([indexBundle.bundleIdentifier hasPrefix:@"com.apple.iokit"]) {
            indexBundle = [NSBundle bundleWithIdentifier:@"com.apple.coretypes"];
        }
        
        NSDictionary *index = typeIndexForBundle(indexBundle);
        if (index.count) {
            NSDictionary *entry = index[lastObject] ?: index[lastObject.stringByDeletingPathExtension];
            
            if (entry) {
                NSArray *utis = entry[ABTypeIndexUTIsKey];
                for (NSString *uti in utis) {
                    NSURL *url = customIconForUTI(uti);
                    
                    NSURL *defaultURL = (__bridge_transfer NSURL *)LSCopyDefaultApplicationURLForContentType((__bridge CFStringRef)uti, 0x00000002, NULL);
                    if (url && [defaultURL isEqualTo:bndl.bundleURL]) {
                        ABLog("PASSED TEST: %@", url);
                        return url;
                    }
                }
                
                NSArray *extensions = entry[ABTypeIndexExtensionsKey];
                for (NSString *ext in extensions) {
                    NSURL *url = customIconForExtension(ext);
                    if (url)
                        return url;
                }
                
                NSArray *ostypes = entry[ABTypeIndexOSTypesKey];
                for (NSString *ostype in ostypes) {
                    NSURL *url = customIconForOSType(ostype);
                    if (url)
                        return url;
                }
            }
        }
    }

    return nil;
}

NSURL *replacementURLForURLRelativeToBundle(NSURL *url, NSBundle *bndl) {
    return resolve(_replacementURLForURLRelativeToBundle(url, bndl));
}

NSURL *replacementURLForURL(NSURL *url) {
    if (!url || !url.isFileURL || ABURLInThemesDirectory(url))
        return nil;
    
    if (url.baseURL) {
        NSBundle *bndl = [NSBundle bundleWithURL:url.baseURL];
        if (bndl.bundleIdentifier)
            return replacementURLForURLRelativeToBundle(url, bndl);
    }
    
    // traverse down path until we get a bundle with an identifier
    BOOL foundBundle = NO;
    NSBundle *bndl = nil;
    NSURL *testURL = [url URLByDeletingLastPathComponent];
    NSUInteger cnt = 0;
    
    // reasonably limit the deep search to 10
    while (![testURL.path isEqualToString:@"/.."] &&
           !foundBundle &&
           cnt++ <= 10) {
        bndl = [NSBundle bundleWithURL:testURL];
        if (bndl.bundleIdentifier) {
            foundBundle = YES;
            break;
        }
        
        testURL = [testURL URLByDeletingLastPathComponent];
    }
    
    return replacementURLForURLRelativeToBundle(url, bndl);
}

static NSURL *_customIconForURL(NSURL *url) {
    if (!url)
        return nil;

    // Step 1, check if our theme structure has a custom icon for this hardcoded
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSURL *testURL = URLForAbsolutePath(url);
    if ([manager fileExistsAtPath:testURL.path isDirectory:&isDir] && !isDir) {
        return [testURL URLByResolvingSymlinksInPath];
    }
    

    return nil;
}

NSURL *customIconForURL(NSURL *url) {
    return resolve(_customIconForURL(url));
}

#pragma mark - UTI Helpers

static NSURL *_customIconForOSType(NSString *type) {
    if (!type || type.length != 4 || [type isEqualToString:@"????"]) {
        return nil;
    }
    
    // step 1, check if we have the actual type.icns
    NSURL *tentativeURL = URLForOSType(type);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2, check this specific type
    tentativeURL = URLForOSType(type);
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 3: get all of the utis for this ostype and check against that
    NSArray *utis = (__bridge_transfer NSArray *)UTTypeCreateAllIdentifiersForTag(kUTTagClassOSType, (__bridge CFStringRef)type, NULL);
    for (NSString *uti in utis) {
        // Use this so it also checks other variants of this extension
        // such as jpeg vs jpg in addition to public.jpeg
        tentativeURL = customIconForUTI(uti);
        if (tentativeURL)
            return [tentativeURL URLByResolvingSymlinksInPath];
    }
    
    return nil;
}

NSURL *customIconForOSType(NSString *type) {
    return resolve(_customIconForOSType(type));
}

static NSURL *_customIconForUTI(NSString *uti) {
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
        tentativeURL = URLForExtension(extension);
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

NSURL *customIconForUTI(NSString *uti) {
    return resolve(_customIconForUTI(uti));
}

static NSURL *_customIconForExtension(NSString *extension) {
    if (!extension)
        return nil;
    
    // step 1, check if we have the actual extension.icns
    NSURL *tentativeURL = URLForExtension(extension);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2, check this specific extension first
    tentativeURL = URLForExtension(extension);
    if ([manager fileExistsAtPath: tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 3: get all of the utis for this extension and check against that
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

NSURL *customIconForExtension(NSString *extension) {
    return resolve(_customIconForExtension(extension));
}
