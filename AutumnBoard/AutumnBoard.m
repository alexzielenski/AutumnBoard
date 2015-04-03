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

static NSString *UTIForURL(CFURLRef url) {
    if (!url)
        return nil;
    NSString *ext = (__bridge_transfer NSString *)CFURLCopyPathExtension(url);
    if (!ext)
        return nil;
    
    NSString *uti = (__bridge_transfer NSString *)(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(ext), NULL));
    BOOL isDir = YES;
    [[NSFileManager defaultManager] fileExistsAtPath:((__bridge NSURL *)url).path isDirectory:&isDir];
    if ((isDir && [uti hasPrefix:@"dyn.age"]) || isDir)
        return nil;
    
    return uti;
}

static NSURL *URLForUTIFile(NSString *name) {
    return [[[ThemePath URLByAppendingPathComponent:@"UTIs"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

static NSURL *customIconForUTI(NSString *uti) {
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

#pragma mark - Hooks
#pragma mark LaunchServices Icon Bindings
static void *(*CreateWithFileInfo)(FSRef const *ref, unsigned long arg1, unsigned short const *arg2, unsigned int arg3, FSCatalogInfo const *arg4, bool arg5);
OPHook6(void *, CreateWithFileInfo, FSRef const *, arg0, unsigned long, arg1, unsigned short const *, arg2, unsigned int, arg3, FSCatalogInfo const *, arg4, BOOL, arg5) {
    
//    void *property = NULL;

    NSURL *targetURL = (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, arg0);
//    if (CFURLCopyResourcePropertyForKey((__bridge CFURLRef)targetURL, CFSTR("_NSURLBindingKey"), NULL, NULL)) {
//        NSLog(@"got binding for %@", targetURL);
//    } else {
//        NSLog(@"didnt get binding for %@", targetURL);
//    }
    
    NSURL *customURL = customIconForURL(targetURL);
    if (customURL) {
        return CreateWithResourceURL((__bridge CFURLRef)customURL, arg5);
    } else {
        // try a UTI
        NSString *uti = UTIForURL((__bridge CFURLRef)(targetURL));
        if (uti) {
            return CreateWithUTI((__bridge CFStringRef)uti, arg1);
        }
    }

    
    return OPOldCall(arg0, arg1, arg2, arg3, arg4, arg5);;
}

static void *(*CreateWithURL)(CFURLRef url, BOOL arg1);
OPHook2(void *, CreateWithURL, CFURLRef, url, BOOL, arg1) {
//    void *property = NULL;
//
//    if (CFURLCopyResourcePropertyForKey(url, CFSTR("_NSURLBindingKey"), (void*)&property, NULL)) {
//        NSLog(@"got binding for %@", url);
//    } else {
//        NSLog(@"didnt get binding for %@", url);
//    }
//    
    NSURL *customURL = customIconForURL((__bridge NSURL *)(url));
    if (customURL) {
        ABLog("got custom URL for URL: %@, %@", customURL, url);
        return CreateWithResourceURL((__bridge CFURLRef)customURL, arg1);
    } else {
//        // try a UTI
//        NSString *uti = UTIForURL(url);
//        if (uti) {
//            return CreateWithUTI((__bridge CFStringRef)uti, arg1);
//        }
    }
    
    return OPOldCall(url, arg1);
}

OPHook2(void *, CreateWithUTI, CFStringRef, uti, BOOL, arg1) {
    ABLog("Snag UTI: %@", uti);
    NSURL *utiPath = customIconForUTI((__bridge NSString *)(uti));
    if (utiPath) {
        return CreateWithResourceURL((__bridge CFURLRef)utiPath, arg1);
    }
    
    return OPOldCall(uti, arg1);
}

// I think these bools tell it to cache the binding
void *(*CreateWithResourceURLAndResourceID)(CFURLRef url, short resourceID, BOOL store);
OPHook3(void *, CreateWithResourceURLAndResourceID, CFURLRef, url, short, resourceID, BOOL, store) {
    ABLog("Create with resource url: %@, %d", url, resourceID);
    return OPOldCall(url, resourceID, store);
}


void *(*CreateWithBookmarkData)(CFDataRef bookmarkData, BOOL arg1);
OPHook2(void *, CreateWithBookmarkData, CFDataRef, bookmarkData, BOOL, arg1) {
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:(__bridge NSData *)bookmarkData
                                                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];
    if (!error && !stale) {
        ABLog("Create with bookmark data: %@", resolved);
        NSURL *customURL = customIconForURL(resolved);
        if (customURL) {
            return CreateWithResourceURL((__bridge CFURLRef)customURL, arg1);
        }
    }
    
    return OPOldCall(bookmarkData, arg1);
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
    if (!error && !stale) {
        ABLog("Create with alias data: %@", resolved);
        NSURL *customURL = customIconForURL(resolved);
        if (customURL) {
            return CreateWithResourceURL((__bridge CFURLRef)customURL, arg1);
        }
    }
    
    return OPOldCall(aliasData, arg1);
}

/*
void *(*CreateWithTypeInfo)(unsigned int arg0, unsigned int arg1, CFStringRef extension, BOOL arg3);
OPHook4(void *, CreateWithTypeInfo, void *, arg0, void *, arg1, CFStringRef, extension, BOOL, arg3) {
    NSLog(@"Create with type info %p, %p, %@, %d", arg0, arg1, extension, arg3);
    return OPOldCall(arg0, arg1, extension, arg3);
}
*/

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
    
    NSBundle *nsBundle = [NSBundle bundleWithPath:((__bridge_transfer NSURL *)CFBundleCopyBundleURL(bundle)).path];
    if (!(hasBundle(nsBundle) && hasResourceForBundle(nsBundle, resourceName, resourceType, subDirName, &finalURL))) {
        finalURL = OPOldCall(bundle, resourceName, resourceType, subDirName);
    } else {
    }
    
    return finalURL;
}

OPHook4(CFURLRef, CFBundleCopyResourceURLInDirectory, CFURLRef, bundleURL, CFStringRef, resourceName, CFStringRef, resourceType, CFStringRef, subDirName) {
    CFURLRef finalURL = NULL;
    
    NSBundle *nsBundle = [NSBundle bundleWithURL:(__bridge NSURL *)bundleURL];
    if (!(hasBundle(nsBundle) && hasResourceForBundle(nsBundle, resourceName, resourceType, subDirName, &finalURL))) {
        finalURL = OPOldCall(bundleURL, resourceName, resourceType, subDirName);
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
#import <mach-o/dyld.h>

/*
                      __ZN10UTIBindingC2EPK10__CFString:        // UTIBinding::UTIBinding(__CFString const*)
 */
void *(*UTIBinding)(CFStringRef uti);
OPHook1(void *, UTIBinding, CFStringRef, uti) {
    NSLog(@"UTIBinding: %@", uti);
    return OPOldCall(CFSTR("public.mp3"));
}

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
    
//    FileInfoBinding = OPFindSymbol("__ZN15FileInfoBindingC2EPK10__CFStringjy");
    
    CreateWithBookmarkData = OPFindSymbol("__ZN14BindingManager22CreateWithBookmarkDataEPK8__CFDatab");
    CreateWithResourceURL = OPFindSymbol("__ZN14BindingManager21CreateWithResourceURLEPK7__CFURLb");
//    CreateWithTypeInfo = OPFindSymbol("__ZN14BindingManager18CreateWithTypeInfoEjjPK10__CFStringb");
    CreateWithFileInfo = OPFindSymbol("__ZN14BindingManager18CreateWithFileInfoEPK5FSRefmPKtjPK13FSCatalogInfob");
    CreateWithURL = OPFindSymbol("__ZN14BindingManager13CreateWithURLEPK7__CFURLb");
    CreateWithUTI = OPFindSymbol("__ZN14BindingManager13CreateWithUTIEPK10__CFStringb");
    CreateWithResourceURLAndResourceID = OPFindSymbol("__ZN14BindingManager34CreateWithResourceURLAndResourceIDEPK7__CFURLsb");
    CreateWithAliasData = OPFindSymbol("__ZN14BindingManager19CreateWithAliasDataEPK8__CFDatab");
    
    UTIBinding = OPFindSymbol("__ZN10UTIBindingC2EPK10__CFString");
//    OPHookFunction(UTIBinding);
    
    __UTTypeCopyIconFileName = OPFindSymbol("__UTTypeCopyIconFileName");
    CGImageReadCreateWithURL = OPFindSymbol("_CGImageReadCreateWithURL");
    
//    OPHookFunction(__UTTypeCopyIconFileName);
//    OPHookFunction(CFURLCreateDataAndPropertiesFromResource);
//    OPHookFunction(FileInfoBinding);
//    OPHookFunction(CreateWithTypeInfo);
//    OPHookFunction(CGImageReadCreateWithURL);
    OPHookFunction(CGImageSourceCreateWithURL);
    OPHookFunction(CGDataProviderCreateWithFilename);
    OPHookFunction(CGDataProviderCreateWithURL);
    OPHookFunction(CFURLCreateData);
    OPHookFunction(CFBundleCopyResourceURLInDirectory);
    OPHookFunction(CFBundleCopyResourceURL);
    
    OPHookFunction(CreateWithAliasData);
    OPHookFunction(CreateWithBookmarkData);
    OPHookFunction(CreateWithResourceURLAndResourceID);
    OPHookFunction(CreateWithURL);
    OPHookFunction(CreateWithFileInfo);
    OPHookFunction(CreateWithUTI);
}
