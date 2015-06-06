//
//  ABBinding.c
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import "ABBinding.h"
#import "ABBindingManager.h"
#import "ABResourceThemer.h"
#import <Opee/Opee.h>

static struct _ABBindingMethodOffsets {
    UInt64 getBindingClass;
    UInt64 getOSType;
    UInt64 copyUTI;
    UInt64 copyDebugDesc;
    UInt64 getBadge;
    UInt64 setBadge;
} ABBindingMethodOffsets;

static struct _ABPropertyOffsets {
    // All Bindings
    UInt64 iconRef;
    
    // Variants
    UInt64 variantType;
    UInt64 variantBinding;
    
    // Links
    UInt64 linkResolvedBinding;
    UInt64 linkURL;
    
    // Composites
    UInt64 compositeForeground;
    UInt64 compositeBackground;
    
    // Bundles
    UInt64 bundleURL;
    
    // File Info
    UInt64 fileInfoExtension;
    
    // Volumes
    UInt64 volumeIconBundleIdentifier;
    UInt64 volumeIconResourceName;
    
    // IconResource
    UInt64 iconResourceURL;
    UInt64 iconResourceFlags;
} ABBindingPropertyOffsets;

static struct _ABBindingMethods {
    // Generic
    ABBindingRef (*RetainBinding)(ABBindingRef binding);
    void (*ReleaseBinding)(ABBindingRef binding);
    void (*overrideBinding)(void *destination, void *custom);
    
    // File Info
    UInt64 (*getFlags)(void *binding);
    
    // Link
    OSErr (*resolveBinding)(void *binding);
} ABBindingMethods;

//OSErr (*__LSGetBindingForTypeInfo)(void* context, OSType type, OSType creator, CFStringRef extension, UInt64 unk, LSRolesMask roles, int arg6, int arg7, int ar8, void **arg9);

//!TODO: move this somewhere nice
// This exists mostly for badge theming, but the various constructors if IconResource
// make for interesting possibilities
void (*IconResourceWithTypeInfo)(void *, void *, UInt64);
OPHook3(void, IconResourceWithTypeInfo, void *, this, OSType, type, UInt64, flags) {
    OPOldCall(this, type, flags);

    NSURL *custom = customIconForOSType(ABStringFromOSType(type));
    if (!custom) {
        CFURLRef orig = ABIconResourceGetURL(this);
        custom = replacementURLForURL((__bridge NSURL *)orig);
    }
    
    if (custom) {
        ABIconResourceSetURL(this, custom);
        ABIconResourceSetFlags(this, flags);
    }
}

void (*IconResourceWithBundle)(void *, CFURLRef, CFStringRef, UInt64);
OPHook4(void, IconResourceWithBundle, void *, this, CFURLRef, url, CFStringRef, name, UInt64, flags) {
    OPOldCall(this, url, name, flags);

    NSBundle *bndl = [NSBundle bundleWithURL:((__bridge NSURL *)url)];
    NSURL *custom = iconForBundle(bndl);
    
    if (custom != nil) {
        ABIconResourceSetFlags(this, flags);
        ABIconResourceSetURL(this, custom);
    }
}

void (*IconResourceWithURL)(void *, CFURLRef, UInt64);
OPHook3(void, IconResourceWithURL, void *, this, CFURLRef, url, UInt64, flags) {
    if ([(__bridge NSURL *)url isKindOfClass:[NSURL class]]) {
        NSURL *replacement = replacementURLForURL((__bridge NSURL *)url);
        if (replacement)
            url = (__bridge CFURLRef)replacement;
    }
    
    OPOldCall(this, url, flags);
}

void (*IconResourceWithFileInfo)(void *, CFStringRef, CFStringRef, UInt64);
OPHook4(void, IconResourceWithFileInfo, void *, this, CFStringRef, uti, CFStringRef, conformance, UInt64, flags) {
    OPOldCall(this, uti, conformance, flags);

    NSURL *custom = customIconForUTI((__bridge NSString *)uti);
    if (custom) {
        ABIconResourceSetURL(this, custom);
        ABIconResourceSetFlags(this, flags);
        return;
    }
    
    custom = replacementURLForURL((__bridge NSURL *)ABIconResourceGetURL(this));
    if (custom) {
        ABIconResourceSetURL(this, custom);
    }
}

void (*IconResourceWithBinding)(void *, void *, void *, UInt64);
OPHook4(void, IconResourceWithBinding, void *, this, void *, context, void **, binding, UInt64, flags) {
    OPOldCall(this, context, binding, flags);
    
    NSURL *custom = replacementURLForURL((__bridge NSURL *)ABIconResourceGetURL(this));
    if (custom) {
        ABIconResourceSetURL(this, custom);
    }
}

OPInitialize {
    if (ABIsInQuickLook() ||!ABIsSupportedVersion())
        return;
    
    void *image = OPGetImageByName("/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/LaunchServices");

    IconResourceWithBinding = OPFindSymbol(image, "__ZN12IconResource10initializeEP9LSContextP9LSBindingy");
    OPHookFunction(IconResourceWithBinding);
    
    IconResourceWithFileInfo = OPFindSymbol(image, "__ZN12IconResourceC1EPK10__CFStringS2_y");
    OPHookFunction(IconResourceWithFileInfo);
    
    IconResourceWithURL = OPFindSymbol(image, "__ZN12IconResourceC1EPKvy");
    OPHookFunction(IconResourceWithURL);
    
    IconResourceWithBundle = OPFindSymbol(image, "__ZN12IconResourceC2EPK7__CFURLPK10__CFStringyy");
    OPHookFunction(IconResourceWithBundle);
    
    IconResourceWithTypeInfo = OPFindSymbol(image, "__ZN12IconResourceC2Ejy");
    OPHookFunction(IconResourceWithTypeInfo);
    
    ABBindingMethods.ReleaseBinding = OPFindSymbol(image, "__ZN14BindingManager7ReleaseEP7Bindingb");
    ABBindingMethods.RetainBinding  = OPFindSymbol(image, "__ZN14BindingManager6RetainEP7Bindingb");

    /**
     This block here gets the offsets relative to the vtable of certain instance methods
     for the Binding C++ subclasses at runtime so we don't have to hardcode the offsets.
     */
    // Get absolute offsets to instance methods
    void *copyUTI         = OPFindSymbol(image, "__ZNK15FileInfoBinding7copyUTIEv");
    void *getType         = OPFindSymbol(image, "__ZNK15FileInfoBinding7getTypeEv");
    void *getBindingClass = OPFindSymbol(image, "__ZNK15FileInfoBinding15getBindingClassEv");
    void *copyDebugDesc   = OPFindSymbol(image, "__ZNK15FileInfoBinding13copyDebugDescEv");
    void *getBadge        = OPFindSymbol(image, "__ZNK15FileInfoBinding8getBadgeEv");
    void *setBadge        = OPFindSymbol(image, "__ZN7Binding8setBadgeEy");

    // Class-specific
    ABBindingMethods.overrideBinding = OPFindSymbol(image, "__ZN7Binding19overrideWithBindingEPS_");
    ABBindingMethods.getFlags        = OPFindSymbol(image, "__ZNK15FileInfoBinding8getFlagsEv");
    ABBindingMethods.resolveBinding  = OPFindSymbol(image, "__ZN11LinkBinding14resolveBindingEv");

    // Lookup offsets to get the instance methods for each binding class
    // and assign the relative one to our struct
    void **bindingVtable = OPFindSymbol(image, "__ZTV15FileInfoBinding");
    
    // vtables begin starting with two zeroes so stop when we find those
    // or if thats not the case we can reasonably limit to searching 64 entries
    for (int x = 2; (bindingVtable[x] != 0x0 || bindingVtable[x+1] != 0x0) && x < 64; x++) {
        void *ptr = bindingVtable[x];
        UInt64 offset = (x - 2) * sizeof(void *);
        if (ptr == copyUTI && ABBindingMethodOffsets.copyUTI == 0)
            ABBindingMethodOffsets.copyUTI         = offset;
        else if (ptr == getType && ABBindingMethodOffsets.getOSType == 0)
            ABBindingMethodOffsets.getOSType       = offset;
        else if (ptr == getBindingClass && ABBindingMethodOffsets.getBindingClass == 0)
            ABBindingMethodOffsets.getBindingClass = offset;
        else if (ptr == copyDebugDesc && ABBindingMethodOffsets.copyDebugDesc == 0)
            ABBindingMethodOffsets.copyDebugDesc   = offset;
        else if (ptr == getBadge && ABBindingMethodOffsets.getBadge == 0)
            ABBindingMethodOffsets.getBadge        = offset;
        else if (ptr == setBadge && ABBindingMethodOffsets.setBadge == 0)
            ABBindingMethodOffsets.setBadge        = offset;
    }
    
    //! OS-Version Specific Offsets
    if (ABLaunchServicesVersionInRange(ABLaunchServicesVersion101002, ABLaunchServicesVersion101003)) {
        struct _ABPropertyOffsets offs = {
            .iconRef                    = 0x8,
            .variantType                = 0x48,
            .variantBinding             = 0x40,
            .linkResolvedBinding        = 0x60,
            .linkURL                    = 0x58,
            .compositeForeground        = 0x40,
            .compositeBackground        = 0x48,
            .bundleURL                  = 0x40,
            .fileInfoExtension          = 0x40,
            .volumeIconBundleIdentifier = 0x48,
            .volumeIconResourceName     = 0x50,
            .iconResourceURL            = 0x0,
            .iconResourceFlags          = 0x8
        };
        
        ABBindingPropertyOffsets = offs;
    }
}

// We sitll need this functionality for absolutes to work
void *ABPairBindingsWithURL(ABBindingRef binding, NSURL *url) {
    ABBindingClass class = ABBindingGetBindingClass(binding);
    void *destination = binding;
    
    NSURL *customURL = customIconForURL(url);

    if (class == ABBindingClassLink && !customURL) {
        // Get the icon ref for the binding that this alias resolves to
        // because the OSType for a link is always 'alis'
        destination = ABLinkBindingResolve(destination);
        class = ABBindingGetBindingClass(destination);
    }
    
    // Our IconResource method wont work for this extensions if its extension/ostype is unknown
    // Since we get the original icon and step backward. We can find by extension this way
    // before it gets to the point
    if (!customURL && class == ABBindingClassFileInfo) {
        NSString *ext = (__bridge NSString *)ABFileInfoBindingGetExtension(destination);
        customURL = customIconForExtension(ext);
        
        if (!customURL) {
            OSType type = ABBindingGetOSType(destination);
            if (type != 0 && type != '????')
                customURL = customIconForOSType(ABStringFromOSType(type));
        }

        if (!customURL) {
            NSString *uti = (__bridge_transfer NSString *)ABBindingCopyUTI(destination);
            //!TODO: add an argument to this method to check explicitly only for this uti
            //!and not equivalent types
            customURL = customIconForUTI(uti);
        }
    }
    
    if (customURL && class != ABBindingClassComposite) {
        customURL = [NSURL URLByResolvingAliasFileAtURL:customURL options:NSURLBookmarkResolutionWithoutUI error:nil] ?: customURL;

        ABBindingRef custom = CreateWithResourceURL((__bridge CFURLRef)[customURL URLByResolvingSymlinksInPath], YES);

        if (custom) {
            // Since these types call back for sidebar implementations we need to make
            // hax by preserving their type and re-registering their icon
            // But you directly set the icon on some badged icons
            // the badge wouldn't show but overriding it will work.
            if (ABBindingGetBadge(destination) == 0 &&
                ABBindingGetBindingClass(binding) != ABBindingClassLink &&
                (class == ABBindingClassFileInfo ||
                class == ABBindingClassUTI ||
                class == ABBindingClassVolume)) {
                ABBindingSetIconRef(binding, ABBindingGetIconRef(custom));
            } else {
                ABBindingOverride(binding, custom);
            }
        }
    } else if (class == ABBindingClassComposite) {
        // recursively apply icons as appropriate to each of the composite's parts
        ABPairBindingsWithURL(ABCompositeBindingGetForegroundBinding(binding), NULL);
        ABPairBindingsWithURL(ABCompositeBindingGetBackgroundBinding(binding), NULL);
    }
    
    return binding;
}

#pragma mark - ABBinding Methods

void ABBindingOverride(ABBindingRef destination, ABBindingRef custom) {
    ABBindingMethods.overrideBinding(destination, custom);
}

CFStringRef ABBindingCopyUTI(ABBindingRef arg0) {
    if (!arg0)
        return NULL;
    
    void *deref = *(void **)arg0;
    
    // big hax to call C++ instance method from C
    CFStringRef (*copyUTI)(ABBindingRef binding);
    copyUTI = *(void **)((uint8_t *)deref + ABBindingMethodOffsets.copyUTI);
    return copyUTI(arg0);
}

UInt32 ABBindingGetOSType(ABBindingRef binding) {
    if (!binding)
        return '????';
    
    void *deref = *(void **)binding;
    
    UInt32 (*getType)(ABBindingRef binding);
    getType = *(void **)((uint8_t *)deref + ABBindingMethodOffsets.getOSType);
    return getType(binding);
}

ABBindingClass ABBindingGetBindingClass(ABBindingRef binding) {
    if (!binding)
        return 0x0;
    
    ABBindingClass (*getClass)(ABBindingRef binding);
    // HEY GUYS LOOK AT ALL THESE CASTS!
    getClass = *(void **)((uint8_t *)(*(void **)binding) + ABBindingMethodOffsets.getBindingClass);
    return getClass(binding);
}

UInt64 ABBindingGetBadge(ABBindingRef binding) {
    UInt64 (*getBadge)(ABBindingRef binding);
    getBadge = *(void **)((uint8_t *)(*(void **)binding) + ABBindingMethodOffsets.getBadge);
    return getBadge(binding);
}

void ABBindingSetBadge(ABBindingRef binding, UInt64 badge) {
    void (*setBadge)(ABBindingRef binding, UInt64 badge);
    setBadge = *(void **)((uint8_t *)(*(void **)binding) + ABBindingMethodOffsets.setBadge);
    setBadge(binding, badge);
}

#pragma mark - ABBinding Variables

IconRef ABBindingGetIconRef(ABBindingRef binding) {
    if (!binding)
        return NULL;
    
    void *iconRef = *(void **)((uint8_t *)binding + ABBindingPropertyOffsets.iconRef);
    if (IsValidIconRef(iconRef))
        return iconRef;
    return NULL;
}

void ABBindingSetIconRef(ABBindingRef binding, IconRef icon) {
    if (binding && IsValidIconRef(icon)) {
        *(IconRef *)((uint8_t *)binding + ABBindingPropertyOffsets.iconRef) = icon;
    }
}

bool ABBindingIsSidebarVariant(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVariant) {
        UInt32 flags = *(OSType *)((uint8_t *)binding + ABBindingPropertyOffsets.variantType);
        return flags != 0;
    }
    
    return false;
}

CFURLRef ABBindingGetURL(ABBindingRef binding) {
    CFURLRef url = ABBundleBindingGetURL(binding) ?: ABLinkBindingGetURL(binding);
    return url;
}

#pragma mark - Class-Specific

ABBindingRef ABLinkBindingResolve(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassLink) {
        // resolveBinding puts the resolved binding into LinkBinding + 0x60
        ABBindingMethods.resolveBinding(binding);
        return *(ABBindingRef *)((uint8_t *)binding + ABBindingPropertyOffsets.linkResolvedBinding);
    }
    return NULL;
}

CFURLRef ABLinkBindingGetURL(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassLink)
        return *(CFURLRef *)((uint8_t *)binding + ABBindingPropertyOffsets.linkURL);
    return NULL;
}

ABBindingRef ABCompositeBindingGetForegroundBinding(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassComposite) {
        return *(ABBindingRef *)((uint8_t *)binding + ABBindingPropertyOffsets.compositeForeground);
    }
    return NULL;
}

ABBindingRef ABCompositeBindingGetBackgroundBinding(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassComposite) {
        return *(ABBindingRef *)((uint8_t *)binding + ABBindingPropertyOffsets.compositeBackground);
    }
    return NULL;
}

CFStringRef ABFileInfoBindingGetExtension(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassFileInfo)
        return *(CFStringRef *)((uint8_t *)binding + ABBindingPropertyOffsets.fileInfoExtension);
    return NULL;
}

UInt64 ABFileInfoBindingGetFlags(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassFileInfo) {
        return ABBindingMethods.getFlags(binding);
    }
    return 0;
}

CFURLRef ABBundleBindingGetURL(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassBundle)
        return *(CFURLRef *)((uint8_t *)binding + ABBindingPropertyOffsets.bundleURL);
    return NULL;
}

ABBindingRef ABVariantBindingGetBinding(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVariant)
        return *(ABBindingRef *)((uint8_t *)binding + ABBindingPropertyOffsets.variantBinding);
    return NULL;
}

CFStringRef ABVolumeBindingGetBundleIdentifier(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVolume)
        return *(CFStringRef *)((uint8_t *)binding + ABBindingPropertyOffsets.volumeIconBundleIdentifier);
    return NULL;
}

CFStringRef ABVolumeBindingGetBundleIconResourceName(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVolume)
        return *(CFStringRef *)((uint8_t *)binding + ABBindingPropertyOffsets.volumeIconResourceName);
    return NULL;
}

NSString *ABBindingCopyDescription(ABBindingRef binding) {
    if (!binding)
        return nil;
    
    void *deref = *(void **)binding;
    
    CFStringRef (*getDesc)(ABBindingRef binding);
    getDesc = *(void **)((uint8_t *)deref + ABBindingMethodOffsets.copyDebugDesc);
    return (__bridge_transfer NSString *)getDesc(binding);
}

#pragma mark - Icon Resource
                      
CFURLRef ABIconResourceGetURL(IconResourceRef resource) {
    if (resource == NULL)
        return NULL;
    return *(CFURLRef *)((uint8_t *)resource + ABBindingPropertyOffsets.iconResourceURL);
}

void ABIconResourceSetURL(IconResourceRef resource, NSURL *url) {
    if (resource == NULL)
        return;
    
    CFURLRef orig = ABIconResourceGetURL(resource);
    if (orig)
        CFRelease(orig);
    *(CFURLRef *)((uint8_t *)resource + ABBindingPropertyOffsets.iconResourceURL) = (__bridge_retained CFURLRef)url.copy;
}

UInt64 ABIconResourceGetFlags(IconResourceRef resource) {
    if (resource == NULL)
        return 0;
    return *(UInt64 *)((uint8_t *)resource + ABBindingPropertyOffsets.iconResourceFlags);
}

void ABIconResourceSetFlags(IconResourceRef resource, UInt64 flags) {
    if (resource == NULL)
        return;
    *(UInt64 *)((uint8_t *)resource + ABBindingPropertyOffsets.iconResourceFlags) = flags;
}
                      
NSString *ABStringFromOSType(OSType type) {
    return (__bridge_transfer NSString *)UTCreateStringForOSType(type);
}
