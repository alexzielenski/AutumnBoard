//
//  AutumnBoard.m
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/1/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Opee/Opee.h>
#import <syslog.h>

static NSURL *ThemePath;

static void *(*CreateWithResourceURL)(CFURLRef url, BOOL arg1);
static void *(*CreateWithUTI)(CFStringRef uti, BOOL arg1);
static void *(*CreateWithLegacyIconRef)(IconRef, BOOL);
static void *(*CreateWithTypeInfo)(OSType arg0, OSType arg1, CFStringRef extension, BOOL arg3);
static void *(*FindAndRetain)(IconRef ref, BOOL arg1);

static NSURL *customIconForUTI(NSString *uti);
static NSURL *customIconForURL(NSURL *url);
static NSURL *customIconForExtension(NSString *extension);
static NSURL *customIconForOSType(NSString *type);

#define OPLogLevelNotice LOG_NOTICE
#define OPLogLevelWarning LOG_WARNING
#define OPLogLevelError LOG_ERR

#define OPLog(level, format, ...) do { \
CFStringRef _formatted = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR(format), ## __VA_ARGS__); \
size_t _size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(_formatted), kCFStringEncodingUTF8); \
char _utf8[_size + sizeof('\0')]; \
CFStringGetCString(_formatted, _utf8, sizeof(_utf8), kCFStringEncodingUTF8); \
CFRelease(_formatted); \
syslog(level, "%s", _utf8); \
} while (false)

//    #define OPLog(TYPE, fmt, ...) CFLog(TYPE, CFSTR("Opee: " fmt), ##__VA_ARGS__)

#pragma mark - ABBinding

#define ABLog(FORMAT, ...) OPLog(OPLogLevelNotice, FORMAT, ## __VA_ARGS__)

static UInt32 ABBindingGetMagic(void *binding) {
    if (!binding)
        return 0;
    
    return *((UInt32 *)binding);
}

// Gets UTI associated with a binding
// + 0x80 is UTI function
// + 0x48 is OS Type
// + 0x40 on Bundle binding is the URL

static CFStringRef ABBindingCopyUTI(void *arg0) {
    void *deref = *(void **)arg0;
    
    // big hax to call C++ instance method from C
    CFStringRef (*copyUTI)(void *binding);
    copyUTI = *(void **)((uint8_t *)deref + 0x80);
    return copyUTI(arg0);
}

static UInt32 ABBindingGetType(void *binding) {
    void *deref = *(void **)binding;
    
    UInt32 (*getType)(void *binding);
    getType = *(void **)((uint8_t *)deref + 0x70);
    return getType(binding);
}

static IconRef ABBindingGetIconRef(void *binding) {
    if (!binding)
        return NULL;
    void *iconRef = *(void **)((uint8_t *)binding + 0x8);
    if (IsValidIconRef(iconRef))
        return iconRef;
    return NULL;
}

static UInt64 ABBindingGetVariantFlags(void *binding) {
    UInt64 (*getFlags)(void *binding);
    // HEY GUYS LOOK AT ALL THESE CASTS!
    getFlags = *(void **)((uint8_t *)(*(void **)binding) + 0x60);
    return getFlags(binding);
}

static BOOL ABBindingIsSidebarVariant(void *binding) {
    if (ABBindingGetVariantFlags(binding) == 0x6) {
        UInt32 flags = *(OSType *)((uint8_t *)binding + 0x48);
        return flags != 0;
    }
    
    return NO;
}

// also holds extension for FileInfoBinding
static void *ABBindingGetVariantBinding(void *binding) {
    return *(void **)((uint8_t *)binding + 0x40);
}

static void ABBindingOverride(void *destination, void *custom) {
    // This is the actual stuff that replaces the icons
    // dont listen to what other people tell you, this IS the magic
    // wtf how does this shit work? you may ask
    // I'll tell you
    
    // 1: Dereference the pointer to the binding so we can interact
    //    with the object itself.
    void *def = *(void **)destination;
    // 2: Create a variable to store the address to the override method
    void (*overrideBinding)(void *dest, void *src);
    // 3: Get and dereference the address to the override binding function on
    //    this C++ instance method
    overrideBinding = *(void **)((uint8_t *)def + 0x68);
    // 4: Invoke it
    overrideBinding(destination, custom);
}

#define ABLogBinding(BINDING) ABLog("Binding: %p (%@)", BINDING, ABBindingGetDescription(BINDING));
static CFStringRef ABBindingGetDescription(void *binding) {
    void *deref = *(void **)binding;
    
    CFStringRef (*getDesc)(void *binding);
    getDesc = *(void **)((uint8_t *)deref + 0x48);
    return getDesc(binding);
}

static NSString *ABStringFromOSType(OSType type) {
    return (__bridge_transfer NSString *)UTCreateStringForOSType(type);
}
// OSType, EXT, UTI, FLAGS
static uint32_t (*GetSidebarVariantType)(OSType type, CFStringRef extension, CFStringRef uti, UInt64 flags);
static void *ABPairBindingsWithURL(void *destination, void *custom, NSURL *url) {
    if (GetSidebarVariantType == NULL) {
        GetSidebarVariantType = OPFindSymbol("__Z21GetSidebarVariantTypejPK10__CFStringS1_y");
    }
    uint32_t destMagic = ABBindingGetMagic(destination) & 0xfff;
    
    // Here are the magic values. For some reason I am only ever able to consistently get the last three bytes of it
    // so we are just checking against those
    // 0x12e560: File Info
    // 0x12e780: Bundle
    // 0x12eb80: UTI
    // 0x12ea50: Volume
    // 0x12e6d0: Custom
    // 0x12e610: Link
    // 0x12e830: Variant
    // 0x1298a0: SideFault
    // 0x12e8e0: Composite

    // We don't want to do this for the bundle binding because they have a different
    // source of icons (they are covered in the nameOfIconFile and customIconForURL)
    // if their icons don't exist
    BOOL sidebar = ABBindingIsSidebarVariant(destination);
    if (destMagic != 0x780 &&
        destMagic != 0x8e0 &&
        destMagic != 0x6d0 &&
        destMagic != 0xa50 &&
        !custom) {
        
        // ABBindingCopyUTI doesnt follow the create rule despite its name
        NSString *uti = (__bridge NSString *)(ABBindingCopyUTI(destination));
        if (uti && UTTypeIsDynamic((__bridge CFStringRef)(uti)))
            uti = nil;
        
        if (uti) {
            NSURL *url = customIconForUTI(uti);
            if (url) {
                custom = CreateWithResourceURL((__bridge CFURLRef)url, YES);
            }
        }
        
        if (url && !custom) {
            // Get the UTI ourselves from the extension or something
            NSURL *customURL = customIconForExtension(url.pathExtension);
            if (customURL)
                custom = CreateWithResourceURL((__bridge CFURLRef)customURL, YES);
        }
        
        if (!custom || sidebar) {
            OSType ostype = ABBindingGetType(destination);
            
            if (sidebar) {
                ostype = GetSidebarVariantType(ABBindingGetType(destination),
                                               NULL,
                                               ABBindingCopyUTI(destination),
                                               ABBindingGetVariantFlags(destination));
            }
            
            // Getting an OS Type off of the path for dirs breaks
            // so use the folder OS Type if this is an unidentifiable directory
            if ((ostype == 0 || ostype == '????') && url && !uti && destMagic != 0x780) {
                // Dont apply the generic folder icon to packages
                    // See if its a dir with a weird extension
                LSItemInfoRecord info;
                LSCopyItemInfoForURL((__bridge CFURLRef)url, kLSRequestBasicFlagsOnly, &info);
                if (info.flags & kLSItemInfoIsPackage)
                    ostype = kGenericExtensionIcon;
                else if (info.flags & kLSItemInfoIsContainer)
                    ostype = kGenericFolderIcon;
            }

            if (ostype != 0 && ostype != '????') {
                NSURL *customURL = customIconForOSType(ABStringFromOSType(ostype));
                if (customURL) {
                    custom = CreateWithResourceURL((__bridge CFURLRef)customURL, YES);
                }
            }
        }
    }
    
    if (custom) {
        // ugh...i hate hax
        if (ABBindingGetVariantFlags(destination) == 0x1 ||
            ABBindingGetVariantFlags(destination) == 0x6) {
            *(IconRef *)((uint8_t *)destination + 0x8) = ABBindingGetIconRef(custom);
        } else
            ABBindingOverride(destination, custom);
    }
    
    return destination;
}

static void *ABPairBindings(void *destination, void *custom) {
    return ABPairBindingsWithURL(destination, custom, NULL);
}

#pragma mark - Bundle Helpers

static NSURL *urlForBundle(NSBundle *bundle) {
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

static BOOL hasBundle(NSBundle *bundle) {
    BOOL isDir = NO;
    NSURL *bundleURL = urlForBundle(bundle);
    if (!bundleURL)
        return NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[bundleURL path] isDirectory:&isDir];
    return (isDir && exists) || [[NSFileManager defaultManager] fileExistsAtPath:[bundleURL.path stringByAppendingPathExtension:@"icns"]];
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

static NSURL *iconForBundle(NSBundle *bundle) {
    // Shortcut so you dont have to make a folder for each app to change its icon
    NSURL *bndlURL = [urlForBundle(bundle) URLByAppendingPathExtension:@"icns"];
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

static BOOL hasResourceForBundle(NSBundle *bundle, CFStringRef resource, CFStringRef resourceType, CFStringRef subDir, CFURLRef *resourceURL) {
    NSURL *finalURL = urlForBundle(bundle);
    if (!finalURL)
        return NO;
    if (!resource)
        return NO;
    
    if (subDir != NULL) {
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
        
        NSURL *iconURL = [urlForBundle(bundle) URLByAppendingPathExtension:@"icns"];
        if (iconURL && [[NSFileManager defaultManager] fileExistsAtPath:iconURL.path]) {
            *resourceURL = (__bridge_retained CFURLRef)iconURL;
            return YES;
        }
    }
    
    if (resourceType != NULL) {
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

static NSURL *replacementURLForURL(NSURL *url) {
    if (!url)
        return nil;
    
    // Step 1, check absolute paths
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSURL *testURL = [ThemePath URLByAppendingPathComponent:url.path];
    if ([manager fileExistsAtPath:testURL.path isDirectory:&isDir] && !isDir) {
        return nil;
        return testURL;
    }
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
    
    if (foundBundle && hasBundle(bndl) && [pathComponents containsObject:@"Resources"]) {
        NSUInteger rsrcIdx = [pathComponents indexOfObject:@"Resources"];
        testURL = urlForBundle(bndl);
        
        for (NSUInteger x =  rsrcIdx + 1; x < pathComponents.count; x++) {
            testURL = [testURL URLByAppendingPathComponent:[pathComponents[x] copy]];
        }
        if ([manager fileExistsAtPath:testURL.path]) {
            return testURL;
        }
    }
    
    return nil;
}

static NSURL *customIconForURL(NSURL *url) {
    if (!url)
        return nil;
    
    // Step 1, check if our theme structure has a custom icon for this hardcoded
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSURL *testURL = [[ThemePath URLByAppendingPathComponent:url.path] URLByAppendingPathExtension:@"icns"];
    if ([manager fileExistsAtPath:testURL.path isDirectory:&isDir] && !isDir) {
        return testURL;
    }
    
    // Step 2, check if this is a bundle
    NSBundle *tentativeBundle = [NSBundle bundleWithURL:url];
    if (tentativeBundle) {
        return iconForBundle(tentativeBundle);
    }
    
    return nil;
}

#pragma mark - UTI Helpers

static NSURL *URLForOSType(NSString *type) {
    return [[[ThemePath URLByAppendingPathComponent:@"OSTypes"] URLByAppendingPathComponent:type] URLByAppendingPathExtension:@"icns"];
}

static NSURL *customIconForOSType(NSString *type) {
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

static NSURL *URLForUTIFile(NSString *name) {
    return [[[ThemePath URLByAppendingPathComponent:@"UTIs"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

static NSURL *customIconForUTI(NSString *uti) {
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

static NSURL *customIconForExtension(NSString *extension) {
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

#pragma mark - Hooks
#pragma mark LaunchServices Icon Bindings
static void *(*CreateWithFileInfo)(FSRef const *ref, unsigned long arg1, unsigned short const *arg2, unsigned int arg3, FSCatalogInfo const *arg4, bool arg5);
OPHook6(void *, CreateWithFileInfo, FSRef const *, ref, UniCharCount, fileNameLength, const UniChar *, fileName, FSCatalogInfoBitmap, inWhichInfo, FSCatalogInfo const *, outInfo, BOOL, arg5) {
    
    NSURL *targetURL = (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, ref);
    void *customBinding = NULL;
    
    NSURL *customURL = customIconForURL(targetURL);
    if (customURL) {
        customBinding = CreateWithResourceURL((__bridge CFURLRef)customURL, arg5);
    }
    
    return ABPairBindingsWithURL(OPOldCall(ref, fileNameLength, fileName, inWhichInfo, outInfo, arg5), customBinding, targetURL);
}

static void *(*CreateWithURL)(CFURLRef url, BOOL arg1);
OPHook2(void *, CreateWithURL, CFURLRef, url, BOOL, arg1) {
    void *customBinding = NULL;
    NSURL *customURL = customIconForURL((__bridge NSURL *)(url));
    if (customURL) {
        customBinding =  CreateWithResourceURL((__bridge CFURLRef)customURL, arg1);
    }
    
    return ABPairBindingsWithURL(OPOldCall(url, arg1), customBinding, (__bridge NSURL *)url);
}

OPHook2(void *, CreateWithUTI, CFStringRef, uti, BOOL, arg1) {
    NSURL *utiPath = customIconForUTI((__bridge NSString *)(uti));
    
    void *customBinding = NULL;
    if (utiPath) {
        customBinding = CreateWithResourceURL((__bridge CFURLRef)utiPath, arg1);
    }
    
    return ABPairBindings(OPOldCall(uti, arg1), customBinding);
}

void *(*CreateWithBookmarkData)(CFDataRef bookmarkData, BOOL arg1);
OPHook2(void *, CreateWithBookmarkData, CFDataRef, bookmarkData, BOOL, arg1) {
    BOOL stale = NO;
    NSError *error = nil;
    void *customBinding = NULL;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:(__bridge NSData *)bookmarkData
                                                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];
    if (!error && !stale) {
        //        ABLog("Create with bookmark data: %@", resolved);
        NSURL *customURL = customIconForURL(resolved);
        if (customURL) {
            customBinding = CreateWithResourceURL((__bridge CFURLRef)customURL, arg1);
        }
    }
    
    return ABPairBindingsWithURL(OPOldCall(bookmarkData, arg1), customBinding, resolved);
}

// This is used in the Finder sidebar
void *(*CreateWithAliasData)(CFDataRef aliasData, BOOL arg1);
OPHook2(void *, CreateWithAliasData, CFDataRef, aliasData, BOOL, arg1) {
    NSData *bookmarkData = (__bridge_transfer NSData *)CFURLCreateBookmarkDataFromAliasRecord(NULL,
                                                                                              aliasData);
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];
    void *customBinding = NULL;
    if (!error && !stale) {
        //        ABLog("Create with alias data: %@", resolved);
        NSURL *customURL = customIconForURL(resolved);
        if (customURL) {
            customBinding = CreateWithResourceURL((__bridge CFURLRef)customURL, arg1);
        }
    }
    
    return ABPairBindingsWithURL(OPOldCall(aliasData, arg1), customBinding, resolved);
}

OPHook4(void *, CreateWithTypeInfo, OSType, creator, OSType, iconType, CFStringRef, extension, BOOL, arg3) {
    
    void *customBinding = NULL;
    if (extension != NULL) {
        NSURL *targetURL = customIconForExtension((__bridge NSString *)(extension));
        if (targetURL) {
            customBinding = CreateWithResourceURL((__bridge CFURLRef)targetURL, arg3);
        }
    }
    
    if (customBinding == NULL) {
        NSString *code = ABStringFromOSType(iconType);
        
        NSURL *custom = customIconForOSType(code);
        if (custom) {
            customBinding = CreateWithResourceURL((__bridge CFURLRef)custom, arg3);
        }
    }
    
    return ABPairBindings(OPOldCall(creator, iconType, extension, arg3), customBinding);
}


void *(*CreateWithFolder)(SInt16 vRefNum, SInt32 parentFolderID, SInt32 folderID, SInt8 attributes, SInt8 accessPrivileges, BOOL arg5);
OPHook6(void *, CreateWithFolder, SInt16, vRefNum, SInt32, parentFolderID, SInt32, folderID, SInt8, attributes, SInt8, accessPrivileges, BOOL, arg5) {
    return ABPairBindings(OPOldCall(vRefNum, parentFolderID, folderID, attributes, accessPrivileges, arg5), NULL);
}

void *(*CreateWithDeviceID)(const char *device, BOOL arg1);
OPHook2(void *, CreateWithDeviceID, const char *, device, BOOL, arg1) {
    ABLog("Create with Device: %s", device);
    return ABPairBindings(OPOldCall(device, arg1), NULL);
}

void *(*CreateVariant)(void *binding, unsigned long long, unsigned long long, BOOL);
OPHook4(void *, CreateVariant, void *, binding, unsigned long long, arg1, unsigned long long, arg2, BOOL, arg3) {
    return ABPairBindings(OPOldCall(binding, arg1, arg2, arg3), NULL);
}

#pragma mark URL Rerouting

OPHook4(CFURLRef, CFBundleCopyResourceURL, CFBundleRef, bundle, CFStringRef, resourceName, CFStringRef, resourceType, CFStringRef, subDirName) {
    CFURLRef finalURL = NULL;
    
    if ([((__bridge NSString *)resourceName).pathExtension isEqualToString:@"icns"] ||
        [((__bridge NSString *)resourceType) isEqualToString:@"icns"]) {
        ABLog("Bundle: %@, %@, %@", bundle, resourceName, resourceType);
    }
    
    // for some reason when I __bridge over cfbundle shit breaks
    NSBundle *nsBundle = [NSBundle bundleWithPath:((__bridge_transfer NSURL *)CFBundleCopyBundleURL(bundle)).path];
    if (!(hasBundle(nsBundle) && hasResourceForBundle(nsBundle, resourceName, resourceType, subDirName, &finalURL))) {
        finalURL = OPOldCall(bundle, resourceName, resourceType, subDirName);
    }
    
    return finalURL;
}

OPHook4(CFURLRef, CFBundleCopyResourceURLInDirectory, CFURLRef, bundleURL, CFStringRef, resourceName, CFStringRef, resourceType, CFStringRef, subDirName) {
    CFURLRef finalURL = NULL;
    
    if (bundleURL) {
        NSBundle *nsBundle = [NSBundle bundleWithURL:(__bridge NSURL *)bundleURL];
        if (!(hasBundle(nsBundle) && hasResourceForBundle(nsBundle, resourceName, resourceType, subDirName, &finalURL))) {
            finalURL = OPOldCall(bundleURL, resourceName, resourceType, subDirName);
        }
    }
    
    if ([((__bridge NSString *)resourceName).pathExtension isEqualToString:@"icns"] ||
        [((__bridge NSString *)resourceType) isEqualToString:@"icns"]) {
        ABLog("Directory: %@, %@, %@ (%@)", bundleURL, resourceName, resourceType, finalURL);
    }
    
    return finalURL;
}

OPHook1(CGDataProviderRef, CGDataProviderCreateWithFilename, const char *, filename) {
    NSURL *url = [NSURL fileURLWithPath:@(filename)];
    if ((url = replacementURLForURL(url))) {
        return OPOldCall(url.path.UTF8String);
    }
    
    return OPOldCall(filename);
}

OPHook1(CGDataProviderRef, CGDataProviderCreateWithURL, CFURLRef, url) {
    if ([((__bridge NSURL *)url).pathExtension isEqualToString:@"icns"]) {
        ABLog("Data provider create %@", url);
    }
    
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(url);
}

OPHook4(CFDataRef, CFURLCreateData, CFAllocatorRef, allocator, CFURLRef, url, CFStringEncoding, encoding, Boolean, escapeWhitespace) {
    if ([((__bridge NSURL *)url).pathExtension isEqualToString:@"icns"]) {
        ABLog("Create Data %@", url);
    }
    
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(allocator, url, encoding, escapeWhitespace);
}

OPHook2(CGImageSourceRef, CGImageSourceCreateWithURL, CFURLRef, url, CFDictionaryRef, options) {
    if ([((__bridge NSURL *)url).pathExtension isEqualToString:@"icns"]) {
        ABLog("Create image source %@", url);
    }
    
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(url, options);
}


// This is only used for CoreTypes.bundle
// all resultant paths are relative to CoreTypes.bundle (including /Contents/Resources etc.)
CFStringRef (*__UTTypeCopyIconFileName)(CFStringRef arg0);
OPHook1(CFStringRef, __UTTypeCopyIconFileName, CFStringRef, arg0) {
    //    NSURL *replaceURL = customIconForUTI((__bridge NSString *)arg0);
    CFStringRef rtn = OPOldCall(arg0);
    ABLog("orig: %@", rtn);
    return rtn;
}

@interface NSImage (Private)
- (void)_drawMappingAlignmentRectToRect:(struct CGRect)arg1 withState:(unsigned long long)arg2 backgroundStyle:(int)arg3 operation:(unsigned long long)arg4 fraction:(double)arg5 flip:(BOOL)arg6 hints:(id)arg7;
@end

ZKSwizzleInterface(ABImage, NSSidebarImage, NSImage)
@implementation ABImage


- (void)_drawMappingAlignmentRectToRect:(struct CGRect)arg1 withState:(unsigned long long)arg2 backgroundStyle:(int)arg3 operation:(unsigned long long)arg4 fraction:(double)arg5 flip:(BOOL)arg6 hints:(id)arg7 {
    [super _drawMappingAlignmentRectToRect:arg1
                                 withState:0x0
                           backgroundStyle:arg2
                                 operation:arg4
                                  fraction:arg5
                                      flip:arg6
                                     hints:arg7];
}
@end

#import <mach-o/dyld.h>

#pragma mark - Initialize
OPInitialize {
    ABLog("AutumnBoard Loaded");
    char argv[MAXPATHLEN];
    unsigned int buffSize = MAXPATHLEN;
    _NSGetExecutablePath(argv, &buffSize);
    
    char *executable = strrchr(argv, '/');
    executable = (executable == NULL) ? argv : executable + 1;

    ThemePath = [NSURL fileURLWithPath:@"/Library/AutumnBoard/Themes/Fladder2"];
    CreateWithBookmarkData = OPFindSymbol("__ZN14BindingManager22CreateWithBookmarkDataEPK8__CFDatab");
    CreateWithResourceURL = OPFindSymbol("__ZN14BindingManager21CreateWithResourceURLEPK7__CFURLb");
    CreateWithTypeInfo = OPFindSymbol("__ZN14BindingManager18CreateWithTypeInfoEjjPK10__CFStringb");
    CreateWithFileInfo = OPFindSymbol("__ZN14BindingManager18CreateWithFileInfoEPK5FSRefmPKtjPK13FSCatalogInfob");
    CreateWithURL = OPFindSymbol("__ZN14BindingManager13CreateWithURLEPK7__CFURLb");
    CreateWithUTI = OPFindSymbol("__ZN14BindingManager13CreateWithUTIEPK10__CFStringb");
    CreateWithAliasData = OPFindSymbol("__ZN14BindingManager19CreateWithAliasDataEPK8__CFDatab");
    CreateWithFolder = OPFindSymbol("__ZN14BindingManager16CreateWithFolderEsiiaab");
    CreateWithLegacyIconRef = OPFindSymbol("__ZN14BindingManager23CreateWithLegacyIconRefEP13OpaqueIconRefb");
    CreateWithDeviceID = OPFindSymbol("__ZN14BindingManager18CreateWithDeviceIDEPKcb");
    CreateVariant = OPFindSymbol("__ZN14BindingManager13CreateVariantEP7Bindingyyb");
    
    __UTTypeCopyIconFileName = OPFindSymbol("__UTTypeCopyIconFileName");
    
    FindAndRetain = OPFindSymbol("__ZN14BindingManager13FindAndRetainEP13OpaqueIconRef");
    
    OPHookFunction(CreateWithTypeInfo);
    OPHookFunction(CreateWithFolder);
    OPHookFunction(CreateWithAliasData);
    OPHookFunction(CreateWithBookmarkData);
    OPHookFunction(CreateWithURL);
    OPHookFunction(CreateWithFileInfo);
    OPHookFunction(CreateWithUTI);
    OPHookFunction(CreateVariant);
    
    OPHookFunction(CFBundleCopyResourceURLInDirectory);
    OPHookFunction(CFBundleCopyResourceURL);
    
    // Quicklook should always return the original image
    //!TODO: Expand this list to photoshop/acorn/preview/pixelmator/sketch
    //! basically anything that has its UTI Role set to editor (viewer?) for the given file
    //! but only for the safety methods CFURLCreateData, CGDataProviderCreateWith(URL/FIlename), CGImageSourceCreatewithURL
    if (strcmp(executable, "quicklookd") == 0 ||
        strcmp(executable, "QuickLookSatellite") == 0) {
        return;
    }
    
    //    OPHookFunction(__UTTypeCopyIconFileName);
    OPHookFunction(CGImageSourceCreateWithURL);
    OPHookFunction(CGDataProviderCreateWithFilename);
    OPHookFunction(CGDataProviderCreateWithURL);
    OPHookFunction(CFURLCreateData);
}
