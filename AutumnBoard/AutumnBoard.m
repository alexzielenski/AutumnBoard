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
void *(*CreateWithTypeInfo)(OSType arg0, OSType arg1, CFStringRef extension, BOOL arg3);

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

#define ABLog(FORMAT, ...) OPLog(OPLogLevelNotice, FORMAT, ## __VA_ARGS__)

static UInt64 ABBindingGetMagic(void *binding) {
    if (!binding)
        return 0;
    
    return *((UInt32 *)binding + 0);
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

static void (*ReleaseBinding)(void *binding);
static void (*FindAndRelease)(IconRef icon);

static void *ABPairBindingsWithURL(void *destination, void *custom, NSURL *url) {
    IconRef destIcon = ABBindingGetIconRef(destination);
    
    void *def = CreateWithLegacyIconRef(destIcon, YES);
    uint32_t magic = ABBindingGetMagic(def) & 0xfff;
    uint32_t destMagic = ABBindingGetMagic(destination) & 0xfff;
    
    // What we are doing here is getting the binding for which the icon of the destination was originally registered
    // and seeing if that specific Binding is a UTI binding or TypeInfo binding meaning that the icon of this specific
    // icon is actually the default one for its type, in this case we can feel safe in replacing it
    
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
    ABLog("Binding UTI %@ %@, %x, (%@)", url.path, ABBindingCopyUTI(destination), magic, ABBindingCopyUTI(def));
    ABLogBinding(destination);
    
    //!TODO: Create a mapping for all OSTypes in IconsCore to a UTI frm CoreTypes.bundle
    //! and then check it against the OSType in (dest + 0x48) where destMagic == 0x560
    if (magic == 0xb80 && !custom) {
        // ABBindingCopyUTI doesnt follow the create rule despite its name
        NSString *uti = (__bridge NSString *)(ABBindingCopyUTI(destination));
        if (uti) {
            ABLog("MATCH PLEASE: %p, %p, %p", destIcon, ABBindingGetIconRef(def), ABBindingGetIconRef(CreateWithUTI((__bridge CFStringRef)uti, YES)));
            
            NSURL *url = customIconForUTI(uti);
            if (url) {
                custom = CreateWithResourceURL((__bridge CFURLRef)url, NO);
            }
        } else if (url) {
            //!TODO: Figure out if this is necessary
            // Get the UTI ourselves from the extension or something
            NSURL *customURL = customIconForExtension(url.pathExtension);
            if (customURL)
                custom = CreateWithResourceURL((__bridge CFURLRef)customURL, NO);
        }
    }
    
    if (!custom) {
        OSType ostype = ABBindingGetType(destination);
        if ([url.pathExtension isEqualToString:@"app"]) {
            NSLog(@"Got Type: %@", ABStringFromOSType(ostype));
        }
        if (ostype != 0 && ostype != '????') {
            NSURL *customURL = customIconForOSType(ABStringFromOSType(ostype));
            if (customURL) {
                custom = CreateWithResourceURL((__bridge CFURLRef)customURL, NO);
            }
        }
    }
    
    
    if (custom) {
        // calls function at *(prt + 0x68) basically
        OverrideIconRef(destIcon, ABBindingGetIconRef(custom));
    } else {
        RemoveIconRefOverride(destIcon);
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
    return iconName;
}

static NSURL *iconForBundle(NSBundle *bundle) {
    // Shortcut so you dont have to make a folder for each app to change its icon
    NSURL *bndlURL = [urlForBundle(bundle) URLByAppendingPathExtension:@"icns"];
    if (bndlURL && [[NSFileManager defaultManager] fileExistsAtPath:bndlURL.path]) {
        return bndlURL;
    }
    
    NSString *iconName = nameOfIconForBundle(bundle);
    if (!iconName) {
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
        finalURL = [finalURL URLByAppendingPathComponent:(__bridge NSString *)(resource)];
        finalURL = [finalURL URLByAppendingPathExtension:(__bridge NSString *)resourceType];
    } else {
        NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:finalURL
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsPackageDescendants
                                                                                error:nil];
        if (!fileNames.count)
            return NO;
        
        BOOL winning = NO;
        for (NSURL *url in fileNames) {
            NSString *name = url.lastPathComponent;
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
        if (hasBundle(tentativeBundle)) {
            return iconForBundle(tentativeBundle);
        }
    }
    
    return nil;
}

#pragma mark - UTI Helpers

static NSURL *URLForUTIFile(NSString *name) {
    return [[[ThemePath URLByAppendingPathComponent:@"UTIs"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

static NSURL *customIconForUTI(NSString *uti) {
    if (!uti)
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

    void *rtn0 = OPOldCall(ref, fileNameLength, fileName, inWhichInfo, outInfo, arg5);

//    unsigned int *rtn = rtn0;

    
   /* if (!customBinding) {
        unsigned long long magic = *((unsigned long long *)rtn);
        unsigned int type = (unsigned int)(magic & 0xfff);
    
        ABLog("Magic SHIT for %@: %x %x", targetURL, (unsigned int)(magic & 0xfff), 0x560);
        if (type == 0xb80) {
            ABLog("It's a UTI");
            
        } else if (type == 0x560) {
            CFStringRef str = *((CFStringRef *)rtn + 8);
            ABLog("Magic String: %@", str);
        } else if (type == 0x780) {
            CFTypeRef unk = *((CFTypeRef *)rtn + 8);
            ABLog("Magic Value: %@", unk);
        }
    }
    void *iconRef = *(void **)((uint8_t *)rtn0 + 0x8);
    ABLog("Icon Ref: %p, %d", iconRef, IsValidIconRef(iconRef));
    */
//    RemoveIconRefOverride(iconRef);
    
//    unsigned int upper = (magic & 0xffff0000);
//    unsigned int lower = (magic & 0xffff);
//    ABLog("Magic for %@ is:", targetURL);
//    for (int x = -4; x <= 8; x++) {
//        ABLog("%x", *(rtn + x));
//    }
    
    return ABPairBindingsWithURL(rtn0, customBinding, targetURL);
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

// I think these bools tell it to cache the binding
void *(*CreateWithResourceURLAndResourceID)(CFURLRef url, short resourceID, BOOL store);
//OPHook3(void *, CreateWithResourceURLAndResourceID, CFURLRef, url, short, resourceID, BOOL, store) {
//    ABLog("Create with resource url: %@, %d", url, resourceID);
//    return OPOldCall(url, resourceID, store);
//}
//

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
    
//    ABLog("Create with folder");
//    NSURL *folderURL = customIconForUTI(@"public.folder");
    void *customBinding = NULL;
//    if (folderURL) {
//        customBinding = CreateWithResourceURL((__bridge CFURLRef)folderURL, arg5);
//    }
//
    return ABPairBindings(OPOldCall(vRefNum, parentFolderID, folderID, attributes, accessPrivileges, arg5), customBinding);
}

void *(*CreateWithDeviceID)(const char *device, BOOL arg1);
OPHook2(void *, CreateWithDeviceID, const char *, device, BOOL, arg1) {
    ABLog("Create with Device: %s", device);
    return ABPairBindings(OPOldCall(device, arg1), NULL);
}

/*
                      __ZN14BindingManager18CreateWithDeviceIDEPKcb:        // BindingManager::CreateWithDeviceID(char const*, bool)
 */

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
    } else {
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

// This is only used for CoreTypes.bundle
// all resultant paths are relative to CoreTypes.bundle (including /Contents/Resources etc.)
CFStringRef (*__UTTypeCopyIconFileName)(CFStringRef arg0);
OPHook1(CFStringRef, __UTTypeCopyIconFileName, CFStringRef, arg0) {
//    NSURL *replaceURL = customIconForUTI((__bridge NSString *)arg0);
    CFStringRef rtn = OPOldCall(arg0);
    ABLog("orig: %@", rtn);
//    if (replaceURL) {
//        ABLog("copy type filename %@", arg0);
//        ABLog("original %@ repalced with %@", OPOldCall(arg0), replaceURL.path);
//        return (__bridge_retained CFURLRef)replaceURL.copy;
//    }
    return rtn;
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

/*
OPHook6(CFDataRef, CFURLCreateDataAndPropertiesFromResource, CFAllocatorRef, alloc, CFURLRef, url, CFDataRef *, resourceData, CFDictionaryRef *, properties, CFArrayRef, desiredProperties, SInt32 *, errorCode) {
    if ([((__bridge NSURL *)url).pathExtension isEqualToString:@"icns"]) {
        ABLog("Create Prop and Resrc %@", url);
    }
    
    if (// CFBundleCopyInfoDictionary() calls this method so we probably want to avoid a stack overflow
        ![((__bridge NSURL *)url).lastPathComponent isEqualToString:@"Info.plist"] &&
        ![((__bridge NSURL *)url).lastPathComponent isEqualToString:@"Info-macos.plist"]) {
        
        NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
        if (replacement)
            url = (__bridge CFURLRef)replacement;
    }
    return OPOldCall(alloc, url, resourceData, properties, desiredProperties, errorCode);
}
*/

OPHook2(CGImageSourceRef, CGImageSourceCreateWithURL, CFURLRef, url, CFDictionaryRef, options) {
    if ([((__bridge NSURL *)url).pathExtension isEqualToString:@"icns"]) {
        ABLog("Create image source %@", url);
    }
    
    NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    return OPOldCall(url, options);
}


void (*CGImageReadCreateWithURL)(CFURLRef arg0, int arg1, int arg2);
/*
 OPHook3(void, CGImageReadCreateWithURL, CFURLRef, url, int, arg1, int, arg2) {
//    ABLog("Read %@", url);
    if ([((__bridge NSURL *)url).pathExtension isEqualToString:@"icns"]) {
        ABLog("Image Read %@", url);
    }
//
    NSURL *replacement = replacementURLForURL(((__bridge NSURL *)url));
//    ABLog("Read %@ and replace %@", url, replacement);
    if (replacement)
        url = (__bridge CFURLRef)replacement;
    
    OPOldCall(url, arg1, arg2);
}
*/

/*
                      __ZN16RegisteredImages22CopyImageByTypeCreatorEjjPP16OpaqueISImageRef:        // RegisteredImages::CopyImageByTypeCreator(unsigned int, unsigned int, OpaqueISImageRef**)*/

void *(*CopyImageByTypeCreator)(OSType creator, OSType type, void **imageRef);
OPHook3(void *, CopyImageByTypeCreator, OSType, creator, OSType, type, void **, imageRef) {
    void *rtn = OPOldCall(creator, type, imageRef);
    ABLog("Copy Image: %p", rtn);
    return rtn;
}

#import <mach-o/dyld.h>

#pragma mark - Initialize
OPInitialize {
    ABLog("AutumnBoard Loaded");
    char argv[MAXPATHLEN];
    unsigned int buffSize = MAXPATHLEN;
    _NSGetExecutablePath(argv, &buffSize);
    
    char *executable = strrchr(argv, '/');
    executable = (executable == NULL) ? argv : executable + 1;
    
    // Quicklook should always return the original image
    //!TODO: Expand this list to photoshop/acorn/preview/pixelmator/sketch
    //! basically anything that has its UTI Role set to editor (viewer?) for the given file
    //! but only for the safety methods CFURLCreateData, CGDataProviderCreateWith(URL/FIlename), CGImageSourceCreatewithURL
    if (strcmp(executable, "quicklookd") == 0 ||
        strcmp(executable, "QuickLookSatellite") == 0) {
        return;
    }
    
    ThemePath = [NSURL fileURLWithPath:@"/Library/AutumnBoard/Themes/Fladder2"];
    
    ReleaseBinding = OPFindSymbol("__ZN14BindingManager7ReleaseEP7Bindingb");
    FindAndRelease = OPFindSymbol("__ZN14BindingManager14FindAndReleaseEP13OpaqueIconRef");
    
    CreateWithBookmarkData = OPFindSymbol("__ZN14BindingManager22CreateWithBookmarkDataEPK8__CFDatab");
    CreateWithResourceURL = OPFindSymbol("__ZN14BindingManager21CreateWithResourceURLEPK7__CFURLb");
    CreateWithTypeInfo = OPFindSymbol("__ZN14BindingManager18CreateWithTypeInfoEjjPK10__CFStringb");
    CreateWithFileInfo = OPFindSymbol("__ZN14BindingManager18CreateWithFileInfoEPK5FSRefmPKtjPK13FSCatalogInfob");
    CreateWithURL = OPFindSymbol("__ZN14BindingManager13CreateWithURLEPK7__CFURLb");
    CreateWithUTI = OPFindSymbol("__ZN14BindingManager13CreateWithUTIEPK10__CFStringb");
    CreateWithResourceURLAndResourceID = OPFindSymbol("__ZN14BindingManager34CreateWithResourceURLAndResourceIDEPK7__CFURLsb");
    CreateWithAliasData = OPFindSymbol("__ZN14BindingManager19CreateWithAliasDataEPK8__CFDatab");
    CreateWithFolder = OPFindSymbol("__ZN14BindingManager16CreateWithFolderEsiiaab");
    CreateWithLegacyIconRef = OPFindSymbol("__ZN14BindingManager23CreateWithLegacyIconRefEP13OpaqueIconRefb");
    CreateWithDeviceID = OPFindSymbol("__ZN14BindingManager18CreateWithDeviceIDEPKcb");
    
    __UTTypeCopyIconFileName = OPFindSymbol("__UTTypeCopyIconFileName");
    CGImageReadCreateWithURL = OPFindSymbol("_CGImageReadCreateWithURL");

    
    CopyImageByTypeCreator = OPFindSymbol("__ZN16RegisteredImages22CopyImageByTypeCreatorEjjPP16OpaqueISImageRef");
    OPHookFunction(CopyImageByTypeCreator);
    
//    OPHookFunction(__UTTypeCopyIconFileName);
//    OPHookFunction(CFURLCreateDataAndPropertiesFromResource);
//    OPHookFunction(FileInfoBinding);
//    OPHookFunction(CGImageReadCreateWithURL);
    OPHookFunction(CGImageSourceCreateWithURL);
    OPHookFunction(CGDataProviderCreateWithFilename);
    OPHookFunction(CGDataProviderCreateWithURL);
    OPHookFunction(CFURLCreateData);
    OPHookFunction(CFBundleCopyResourceURLInDirectory);
    OPHookFunction(CFBundleCopyResourceURL);
    
    OPHookFunction(CreateWithTypeInfo);
    OPHookFunction(CreateWithFolder);
    OPHookFunction(CreateWithAliasData);
    OPHookFunction(CreateWithBookmarkData);
    OPHookFunction(CreateWithURL);
    OPHookFunction(CreateWithFileInfo);
//    OPHookFunction(CreateWithUTI);
}
