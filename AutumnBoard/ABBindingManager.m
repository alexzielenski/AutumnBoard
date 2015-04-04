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
static void *(*CreateVariant)(void *binding, unsigned long long, unsigned long long, BOOL);

OPHook6(void *, CreateWithFileInfo, FSRef const *, ref, UniCharCount, fileNameLength, const UniChar *, fileName, FSCatalogInfoBitmap, inWhichInfo, FSCatalogInfo const *, outInfo, BOOL, arg5) {
    
    NSURL *targetURL = (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, ref);
    return ABPairBindingsWithURL(OPOldCall(ref, fileNameLength, fileName, inWhichInfo, outInfo, arg5), targetURL);
}

OPHook2(void *, CreateWithURL, CFURLRef, url, BOOL, arg1) {
    return ABPairBindingsWithURL(OPOldCall(url, arg1),(__bridge NSURL *)url);
}

OPHook2(void *, CreateWithUTI, CFStringRef, uti, BOOL, arg1) {
    return ABPairBindingsWithURL(OPOldCall(uti, arg1), NULL);
}

OPHook2(void *, CreateWithBookmarkData, CFDataRef, bookmarkData, BOOL, arg1) {
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:(__bridge NSData *)bookmarkData
                                                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];

    
    return ABPairBindingsWithURL(OPOldCall(bookmarkData, arg1), resolved);
}

// This is used in the Finder sidebar
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
    if (error || stale) {
        resolved = nil;
    }
    
    return ABPairBindingsWithURL(OPOldCall(aliasData, arg1), resolved);
}

OPHook4(void *, CreateWithTypeInfo, OSType, creator, OSType, iconType, CFStringRef, extension, BOOL, arg3) {
    
//    void *customBinding = NULL;
//    if (extension != NULL) {
//        NSURL *targetURL = customIconForExtension((__bridge NSString *)(extension));
//        if (targetURL) {
//            customBinding = CreateWithResourceURL((__bridge CFURLRef)targetURL, arg3);
//        }
//    }
//    
//    if (customBinding == NULL) {
//        NSString *code = ABStringFromOSType(iconType);
//        
//        NSURL *custom = customIconForOSType(code);
//        if (custom) {
//            customBinding = CreateWithResourceURL((__bridge CFURLRef)custom, arg3);
//        }
//    }
//    
    return ABPairBindingsWithURL(OPOldCall(creator, iconType, extension, arg3), NULL);
}

OPHook6(void *, CreateWithFolder, SInt16, vRefNum, SInt32, parentFolderID, SInt32, folderID, SInt8, attributes, SInt8, accessPrivileges, BOOL, arg5) {
    return ABPairBindingsWithURL(OPOldCall(vRefNum, parentFolderID, folderID, attributes, accessPrivileges, arg5), NULL);
}

OPHook2(void *, CreateWithDeviceID, const char *, device, BOOL, arg1) {
    ABLog("Create with Device: %s", device);
    return ABPairBindingsWithURL(OPOldCall(device, arg1), NULL);
}

OPHook4(void *, CreateVariant, void *, binding, unsigned long long, arg1, unsigned long long, arg2, BOOL, arg3) {
    return ABPairBindingsWithURL(OPOldCall(binding, arg1, arg2, arg3), NULL);
}

OPInitialize {
    if (ABIsInQuicklook())
        return;
    
    void *image = OPGetImageByName("/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/LaunchServices");
    CreateWithBookmarkData  = OPFindSymbol(image, "__ZN14BindingManager22CreateWithBookmarkDataEPK8__CFDatab");
    CreateWithResourceURL   = OPFindSymbol(image, "__ZN14BindingManager21CreateWithResourceURLEPK7__CFURLb");
    CreateWithTypeInfo      = OPFindSymbol(image, "__ZN14BindingManager18CreateWithTypeInfoEjjPK10__CFStringb");
    CreateWithFileInfo      = OPFindSymbol(image, "__ZN14BindingManager18CreateWithFileInfoEPK5FSRefmPKtjPK13FSCatalogInfob");
    CreateWithURL           = OPFindSymbol(image, "__ZN14BindingManager13CreateWithURLEPK7__CFURLb");
    CreateWithUTI           = OPFindSymbol(image, "__ZN14BindingManager13CreateWithUTIEPK10__CFStringb");
    CreateWithAliasData     = OPFindSymbol(image, "__ZN14BindingManager19CreateWithAliasDataEPK8__CFDatab");
    CreateWithFolder        = OPFindSymbol(image, "__ZN14BindingManager16CreateWithFolderEsiiaab");
    CreateWithLegacyIconRef = OPFindSymbol(image, "__ZN14BindingManager23CreateWithLegacyIconRefEP13OpaqueIconRefb");
    CreateWithDeviceID      = OPFindSymbol(image, "__ZN14BindingManager18CreateWithDeviceIDEPKcb");
    CreateVariant           = OPFindSymbol(image, "__ZN14BindingManager13CreateVariantEP7Bindingyyb");
    
    OPHookFunction(CreateWithDeviceID);
    OPHookFunction(CreateWithTypeInfo);
    OPHookFunction(CreateWithFolder);
    OPHookFunction(CreateWithAliasData);
    OPHookFunction(CreateWithBookmarkData);
    OPHookFunction(CreateWithURL);
    OPHookFunction(CreateWithFileInfo);
    OPHookFunction(CreateWithUTI);
    OPHookFunction(CreateVariant);
}
