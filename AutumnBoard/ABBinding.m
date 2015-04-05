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

static UInt32 ABBindingGetMagic(ABBindingRef binding);
static CFStringRef ABBindingCopyUTI(ABBindingRef arg0);

static ABBindingClass ABBindingGetBindingClass(ABBindingRef binding);
static bool ABBindingIsSidebarVariant(ABBindingRef binding);
static void ABBindingOverride(ABBindingRef destination, ABBindingRef custom);

static NSString *ABBindingCopyDescription(ABBindingRef binding);
static CFURLRef ABBindingGetURL(ABBindingRef binding);
static UInt32 ABBindingGetOSType(ABBindingRef binding);
static IconRef ABBindingGetIconRef(ABBindingRef binding);
static void ABBindingSetIconRef(ABBindingRef binding, IconRef icon);

static CFURLRef ABLinkBindingGetURL(ABBindingRef binding);
static CFURLRef ABBundleBindingGetURL(ABBindingRef binding);
static CFStringRef ABFileInfoBindingGetExtension(ABBindingRef binding);
static UInt64 ABFileInfoBindingInfoGetFlags(ABBindingRef binding);
static CFStringRef ABVolumeBindingGetBundleIdentifier(ABBindingRef binding);
static CFStringRef ABVolumeBindingGetBundleIconResourceName(ABBindingRef binding);

static ABBindingRef ABLinkBindingResolve(ABBindingRef binding);
static ABBindingRef ABVariantBindingGetBinding(ABBindingRef binding);
static ABBindingRef ABCompositeBindingGetForegroundBinding(ABBindingRef binding);
static ABBindingRef ABCompositeBindingGetBackgroundBinding(ABBindingRef binding);

static void *(*RetainBinding)(ABBindingRef binding, BOOL arg1);
static void *(*ReleaseBinding)(ABBindingRef binding, BOOL arg1);
OPInitialize {
    ReleaseBinding = OPFindSymbol(NULL, "__ZN14BindingManager7ReleaseEP7Bindingb");
    RetainBinding = OPFindSymbol(NULL, "__ZN14BindingManager6RetainEP7Bindingb");
}

// OSType, EXT, UTI, FLAGS
static uint32_t (*GetSidebarVariantType)(OSType type, CFStringRef extension, CFStringRef uti, UInt64 flags);
void *ABPairBindingsWithURL(ABBindingRef binding, NSURL *url) {
    if (GetSidebarVariantType == NULL) {
        GetSidebarVariantType = OPFindSymbol(NULL, "__Z21GetSidebarVariantTypejPK10__CFStringS1_y");
    }
    void *destination = binding;
    
    // We don't want to do this for the bundle binding because they have a different
    // source of icons (they are covered in the nameOfIconFile and customIconForURL)
    // if their icons don't exist
    ABBindingClass class = ABBindingGetBindingClass(destination);
    BOOL sidebar = ABBindingIsSidebarVariant(destination);
    NSURL *customURL = customIconForURL(url);
    
    // try first to get an icon for the bundle
    // the iconForBundle function handles the case where
    // the bundle has no specified icon file and therefore fills
    // it in with the appropriate icon for its ostype
    if (class == ABBindingClassBundle && !customURL) {
        NSURL *bundleURL = (__bridge NSURL *)(ABBindingGetURL(destination));
        if (bundleURL.isFileURL)
            customURL = iconForBundle([NSBundle bundleWithURL:bundleURL]);
        
    // VolumeBindings store the identifier for the bundle that the image name will be found in
    // so to support theming of default volume icons we can cheat by taking those and calling our
    // hook of CFBundleCopyResourceURL
    } else if (class == ABBindingClassVolume && !customURL) {
        NSString *identifier = (__bridge NSString *)(ABVolumeBindingGetBundleIdentifier(destination));
        NSString *imageName = (__bridge NSString *)(ABVolumeBindingGetBundleIconResourceName(destination));
        if (identifier.length && imageName.length) {
            NSBundle *bndl = [NSBundle bundleWithIdentifier:identifier];
            customURL = [bndl URLForResource:imageName.stringByDeletingPathExtension withExtension:imageName.pathExtension];
        }
    }
    
    // Get the icon ref for the binding that this alias resolves to
    // because the OSType for a link is always 'alis'
    if (class == ABBindingClassLink) {
        destination = ABLinkBindingResolve(destination);
    }
    
    // Dont fuck with custom icons
    // Dont fuck with bundles
    // I don't know what a SideFault file is – maybe an iCloud document?
    // Composites are handled recursively at the bottom of this method
    if (class != ABBindingClassBundle &&
        class != ABBindingClassSideFault &&
        class != ABBindingClassCustom &&
        class != ABBindingClassComposite &&
        !customURL) {
        
        // ABBindingCopyUTI doesnt follow the create rule despite its name
        NSString *uti = (__bridge NSString *)(ABBindingCopyUTI(destination));
        // A dynamic UTI is no UTI at all (dynamic utis are generated based on the extension/ostype)
        if (uti && UTTypeIsDynamic((__bridge CFStringRef)(uti)))
            uti = nil;
        
        // see if we theme this UTI or any of its associated extensions/ostypes
        customURL = customIconForUTI(uti);
        
        if (url && !customURL) {
            // Get the UTI ourselves from the extension or something
            NSString *ext = url.pathExtension ?: (__bridge NSString *)ABFileInfoBindingGetExtension(destination);
            customURL = customIconForExtension(ext);
        }
        
        if (!customURL || sidebar) {
            OSType ostype = ABBindingGetOSType(destination);
                        
            if (sidebar) {
                ostype = GetSidebarVariantType(ABBindingGetOSType(destination),
                                               NULL,
                                               ABBindingCopyUTI(destination),
                                               ABFileInfoBindingInfoGetFlags(destination));
            }
            
            // Getting an OS Type off of the path for dirs breaks
            // so use the folder OS Type if this is an unidentifiable directory
            if ((ostype == 0 || ostype == '????') && url && !uti &&
                class != ABBindingClassBundle &&
                class != ABBindingClassVolume) {
                
                // Dont apply the generic folder icon to packages
                // See if its a dir with a weird extension
                // (folders like MYFOLDER.3 should get the generic icon but the 3 throws
                // the OSType generator off so we have to hardcode it)
                LSItemInfoRecord info;
                NSURL *resolved = [NSURL URLByResolvingAliasFileAtURL:url
                                                              options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                                                                error:nil];
                LSCopyItemInfoForURL((__bridge CFURLRef)resolved, kLSRequestBasicFlagsOnly, &info);
                
                // Packages get the little lego cube
                if (info.flags & kLSItemInfoIsPackage)
                    ostype = kGenericExtensionIcon;
                // Folders get the generic folder
                else if (info.flags & kLSItemInfoIsContainer)
                    ostype = kGenericFolderIcon;
                // Executables get the executable icon
                else if (ABFileInfoBindingInfoGetFlags(destination) == 1) // executable
                    ostype = 'xTol';
                // Otherwise try to use the LaunchServices ostype (which is likely still '????')
                else
                    ostype = info.filetype;
            }
            
            if (ostype != 0 && ostype != '????')
                customURL = customIconForOSType(ABStringFromOSType(ostype));
        }
        
    }
    
    if (customURL && class != ABBindingClassComposite) {
        ABBindingRef custom = CreateWithResourceURL((__bridge CFURLRef)customURL, YES);
        if (custom) {
            // Since these types call back for sidebar implementations we need to make
            // hax by preserving their type and re-registering their icon
            if (class == ABBindingClassFileInfo ||
                class == ABBindingClassUTI ||
                class == ABBindingClassVolume) {
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

#pragma mark - ABBinding
// Probably useless now that i found ABBindingGetBindingClass
static UInt32 ABBindingGetMagic(ABBindingRef binding) {
    if (!binding)
        return 0;
    
    return *((UInt32 *)binding);
}

// Gets UTI associated with a binding
// + 0x80 is UTI function
// + 0x48 is OS Type
// + 0x40 on Bundle binding is the URL
//!TODO: See if it is instead better to get the symbol for each of the
//! copyUTI methods for every binding class and then use a switch statement
//! deciding which one to call
static CFStringRef ABBindingCopyUTI(ABBindingRef arg0) {
    if (!arg0)
        return NULL;
    
    void *deref = *(void **)arg0;
    
    // big hax to call C++ instance method from C
    CFStringRef (*copyUTI)(ABBindingRef binding);
    copyUTI = *(void **)((uint8_t *)deref + 0x80);
    return copyUTI(arg0);
}

static UInt32 ABBindingGetOSType(ABBindingRef binding) {
    if (!binding)
        return '????';
    
    void *deref = *(void **)binding;
    
    UInt32 (*getType)(ABBindingRef binding);
    getType = *(void **)((uint8_t *)deref + 0x70);
    return getType(binding);
}

static IconRef ABBindingGetIconRef(ABBindingRef binding) {
    if (!binding)
        return NULL;
    
    void *iconRef = *(void **)((uint8_t *)binding + 0x8);
    if (IsValidIconRef(iconRef))
        return iconRef;
    return NULL;
}

static void ABBindingSetIconRef(ABBindingRef binding, IconRef icon) {
    if (binding && IsValidIconRef(icon)) {
        *(IconRef *)((uint8_t *)binding + 0x8) = icon;
    }
}

static ABBindingClass ABBindingGetBindingClass(ABBindingRef binding) {
    if (!binding)
        return 0x0;
    
    ABBindingClass (*getClass)(ABBindingRef binding);
    // HEY GUYS LOOK AT ALL THESE CASTS!
    getClass = *(void **)((uint8_t *)(*(void **)binding) + 0x60);
    return getClass(binding);
}

static bool ABBindingIsSidebarVariant(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVariant) {
        UInt32 flags = *(OSType *)((uint8_t *)binding + 0x48);
        return flags != 0;
    }
    
    return false;
}

static void ABBindingOverride(ABBindingRef destination, ABBindingRef custom) {
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

static CFURLRef ABBindingGetURL(ABBindingRef binding) {
    CFURLRef url = ABBundleBindingGetURL(binding) ?: ABLinkBindingGetURL(binding);
    return url;
}

#pragma mark - Class-Specific

static ABBindingRef ABLinkBindingResolve(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassLink) {
        static ABBindingRef (*resolveBinding)(ABBindingRef binding) = NULL;
        if (!resolveBinding) {
            resolveBinding = OPFindSymbol(NULL, "__ZN11LinkBinding14resolveBindingEv");
        }
        if (resolveBinding) {
            // resolveBinding puts the resolved binding into LinkBinding + 0x60
            resolveBinding(binding);
            return *(ABBindingRef *)((uint8_t *)binding + 0x60);
        }
    }
    return NULL;
}

static CFURLRef ABLinkBindingGetURL(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassLink)
        return *(CFURLRef *)((uint8_t *)binding + 0x58);
    return NULL;
}

static ABBindingRef ABCompositeBindingGetForegroundBinding(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassComposite) {
        return *(ABBindingRef *)((uint8_t *)binding + 0x40);
    }
    return NULL;
}

static ABBindingRef ABCompositeBindingGetBackgroundBinding(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassComposite) {
        return *(ABBindingRef *)((uint8_t *)binding + 0x48);
    }
    return NULL;
}

static CFStringRef ABFileInfoBindingGetExtension(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassFileInfo)
        return *(CFStringRef *)((uint8_t *)binding + 0x40);
    return NULL;
}

static UInt64 ABFileInfoBindingInfoGetFlags(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassFileInfo) {
        return *(UInt64 *)((uint8_t *)binding + 0x50);
    }
    return 0;
}

static CFURLRef ABBundleBindingGetURL(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassBundle)
        return *(CFURLRef *)((uint8_t *)binding + 0x40);
    return NULL;
}

static ABBindingRef ABVariantBindingGetBinding(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVariant)
        return *(ABBindingRef *)((uint8_t *)binding + 0x40);
    return NULL;
}

static CFStringRef ABVolumeBindingGetBundleIdentifier(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVolume)
        return *(CFStringRef *)((uint8_t *)binding + 0x48);
    return NULL;
}

static CFStringRef ABVolumeBindingGetBundleIconResourceName(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassVolume)
        return *(CFStringRef *)((uint8_t *)binding + 0x50);
    return NULL;
}

static NSString *ABBindingCopyDescription(ABBindingRef binding) {
    void *deref = *(void **)binding;
    
    CFStringRef (*getDesc)(ABBindingRef binding);
    getDesc = *(void **)((uint8_t *)deref + 0x48);
    return (__bridge_transfer NSString *)getDesc(binding);
}

NSString *ABStringFromOSType(OSType type) {
    return (__bridge_transfer NSString *)UTCreateStringForOSType(type);
}
