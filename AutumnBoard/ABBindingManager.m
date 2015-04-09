//
//  ABBindingManager.c
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import "ABResourceThemer.h"
#import "ABBindingManager.h"
#import "ABBinding.h"
#import "ABLogging.h"
#import <Opee/Opee.h>

static void *(*CreateWithUTI)(CFStringRef uti, BOOL arg1);
static void *(*CreateWithLegacyIconRef)(IconRef, BOOL);
static void *(*CreateWithTypeInfo)(OSType arg0, OSType arg1, CFStringRef extension, BOOL arg3);
static void *(*CreateWithFileInfo)(FSRef const *ref, unsigned long arg1, unsigned short const *arg2, unsigned int arg3, FSCatalogInfo const *arg4, bool arg5);
static void *(*CreateWithURL)(CFURLRef url, BOOL arg1);
static void *(*CreateWithBookmarkData)(CFDataRef bookmarkData, BOOL arg1);
static void *(*CreateWithAliasData)(CFDataRef aliasData, BOOL arg1);
static void *(*CreateWithFolder)(SInt16 vRefNum, SInt32 parentFolderID, SInt32 folderID, SInt8 attributes, SInt8 accessPrivileges, BOOL arg5);
static void *(*CreateWithDeviceID)(const char *device, BOOL arg1);
static void *(*CreateVariant)(ABBindingRef binding, unsigned long long, unsigned long long, BOOL);
static ABBindingRef (*CreateWithCompositeComponents)(ABBindingRef, ABBindingRef, BOOL);
static ABBindingRef (*CreateWithSideFaultFile)(CFURLRef, BOOL);
static ABBindingRef (*CreateWithData)(CFDataRef, BOOL);

#pragma mark - Hooks

OPHook6(ABBindingRef, CreateWithFileInfo, FSRef const *, ref, UniCharCount, fileNameLength, const UniChar *, fileName, FSCatalogInfoBitmap, inWhichInfo, FSCatalogInfo const *, outInfo, BOOL, arg5) {
    
    NSURL *targetURL = (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, ref);
    return ABPairBindingsWithURL(OPOldCall(ref, fileNameLength, fileName, inWhichInfo, outInfo, arg5), targetURL);
}

OPHook2(ABBindingRef, CreateWithURL, CFURLRef, url, BOOL, arg1) {
    return ABPairBindingsWithURL(OPOldCall(url, arg1),(__bridge NSURL *)url);
}

OPHook2(ABBindingRef, CreateWithUTI, CFStringRef, uti, BOOL, arg1) {
    return ABPairBindingsWithURL(OPOldCall(uti, arg1), NULL);
}

// I don't really know what the difference between BookmarkData and aliasData is but who cares
OPHook2(ABBindingRef, CreateWithBookmarkData, CFDataRef, bookmarkData, BOOL, arg1) {
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:(__bridge NSData *)bookmarkData
                                                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];
    if (error || stale) {
        resolved = nil;
    }
    
    return ABPairBindingsWithURL(OPOldCall(bookmarkData, arg1), resolved);
}

// This is used in the Finder sidebar
OPHook2(ABBindingRef, CreateWithAliasData, CFDataRef, aliasData, BOOL, arg1) {
    NSData *bookmarkData = (__bridge_transfer NSData *)CFURLCreateBookmarkDataFromAliasRecord(NULL,
                                                                                              aliasData);
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];
    if (error || stale) {
        resolved = nil;
    }
    
    return ABPairBindingsWithURL(OPOldCall(aliasData, arg1), resolved);
}

// Asks for an icon given type information such as ostype and extension
OPHook4(ABBindingRef, CreateWithTypeInfo, OSType, creator, OSType, iconType, CFStringRef, extension, BOOL, arg3) {
    return ABPairBindingsWithURL(OPOldCall(creator, iconType, extension, arg3), NULL);
}

OPHook6(ABBindingRef, CreateWithFolder, SInt16, vRefNum, SInt32, parentFolderID, SInt32, folderID, SInt8, attributes, SInt8, accessPrivileges, BOOL, arg5) {
    return ABPairBindingsWithURL(OPOldCall(vRefNum, parentFolderID, folderID, attributes, accessPrivileges, arg5), NULL);
}

OPHook2(ABBindingRef, CreateWithDeviceID, const char *, device, BOOL, arg1) {
    ABLog("Create with Device: %s", device);
    return ABPairBindingsWithURL(OPOldCall(device, arg1), NULL);
}

OPHook4(ABBindingRef, CreateVariant, void *, binding, unsigned long long, arg1, unsigned long long, arg2, BOOL, arg3) {
    return ABPairBindingsWithURL(OPOldCall(binding, arg1, arg2, arg3), NULL);
}

OPHook3(ABBindingRef, CreateWithCompositeComponents, ABBindingRef, foreground, ABBindingRef, background, BOOL, flag) {
    ABLog("COMPOSITES!");
    return ABPairBindingsWithURL(OPOldCall(foreground, background, flag), NULL);
}

OPHook2(ABBindingRef, CreateWithSideFaultFile, CFURLRef, url, BOOL, flag) {
    ABLog("SIDEFAULT!: %@", url);
    return ABPairBindingsWithURL(OPOldCall(url, flag), (__bridge NSURL *)(url));
}

//OPHook2(ABBindingRef, CreateWithData, CFDataRef, data, BOOL, flag) {
//    ABBindingRef rtn = OPOldCall(data, flag);
//    ABLog("CREATE WITH DATA: %@", ABBindingCopyDescription(rtn));
//    return rtn;
//}

OPInitialize {
    if (!ABIsSupportedVersion() || ABIsInQuickLook())
        return;
    
    void *image = OPGetImageByName("/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/LaunchServices");
    CreateWithBookmarkData        = OPFindSymbol(image, "__ZN14BindingManager22CreateWithBookmarkDataEPK8__CFDatab");
    CreateWithResourceURL         = OPFindSymbol(image, "__ZN14BindingManager21CreateWithResourceURLEPK7__CFURLb");
    CreateWithTypeInfo            = OPFindSymbol(image, "__ZN14BindingManager18CreateWithTypeInfoEjjPK10__CFStringb");
    CreateWithFileInfo            = OPFindSymbol(image, "__ZN14BindingManager18CreateWithFileInfoEPK5FSRefmPKtjPK13FSCatalogInfob");
    CreateWithURL                 = OPFindSymbol(image, "__ZN14BindingManager13CreateWithURLEPK7__CFURLb");
    CreateWithUTI                 = OPFindSymbol(image, "__ZN14BindingManager13CreateWithUTIEPK10__CFStringb");
    CreateWithAliasData           = OPFindSymbol(image, "__ZN14BindingManager19CreateWithAliasDataEPK8__CFDatab");
    CreateWithFolder              = OPFindSymbol(image, "__ZN14BindingManager16CreateWithFolderEsiiaab");
    CreateWithLegacyIconRef       = OPFindSymbol(image, "__ZN14BindingManager23CreateWithLegacyIconRefEP13OpaqueIconRefb");
    CreateWithDeviceID            = OPFindSymbol(image, "__ZN14BindingManager18CreateWithDeviceIDEPKcb");
    CreateVariant                 = OPFindSymbol(image, "__ZN14BindingManager13CreateVariantEP7Bindingyyb");
    CreateWithCompositeComponents = OPFindSymbol(image, "__ZN14BindingManager29CreateWithCompositeComponentsEP7BindingS1_b");
    CreateWithSideFaultFile = OPFindSymbol(image, "__ZN14BindingManager23CreateWithSideFaultFileEPK7__CFURLb");
    CreateWithData = OPFindSymbol(image, "__ZN14BindingManager14CreateWithDataEPK8__CFDatab");
    
    OPHookFunction(CreateWithDeviceID);
    OPHookFunction(CreateWithTypeInfo);
    OPHookFunction(CreateWithFolder);
    OPHookFunction(CreateWithAliasData);
    OPHookFunction(CreateWithBookmarkData);
    OPHookFunction(CreateWithURL);
    OPHookFunction(CreateWithFileInfo);
    OPHookFunction(CreateWithUTI);
    OPHookFunction(CreateVariant);
    OPHookFunction(CreateWithCompositeComponents);
    OPHookFunction(CreateWithSideFaultFile);
//    OPHookFunction(CreateWithData);
}
