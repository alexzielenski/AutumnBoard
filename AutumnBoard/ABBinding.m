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
static UInt32 ABBindingGetOSType(ABBindingRef binding);
static IconRef ABBindingGetIconRef(ABBindingRef binding);
static void ABBindingSetIconRef(ABBindingRef binding, IconRef icon);
static ABBindingClass ABBindingGetBindingClass(ABBindingRef binding);
static bool ABBindingIsSidebarVariant(ABBindingRef binding);
static void ABBindingOverride(ABBindingRef destination, ABBindingRef custom);
static CFStringRef ABBindingGetDescription(ABBindingRef binding);

static CFURLRef ABBundleBindingGetURL(ABBindingRef binding);
static CFStringRef ABFileInfoBindingGetExtension(ABBindingRef binding);
static ABBindingRef ABVariantBindingGetBinding(ABBindingRef binding);

// OSType, EXT, UTI, FLAGS
static uint32_t (*GetSidebarVariantType)(OSType type, CFStringRef extension, CFStringRef uti, UInt64 flags);
void *ABPairBindingsWithURL(ABBindingRef destination, NSURL *url) {
    if (GetSidebarVariantType == NULL) {
        GetSidebarVariantType = OPFindSymbol(NULL, "__Z21GetSidebarVariantTypejPK10__CFStringS1_y");
    }
    
    // We don't want to do this for the bundle binding because they have a different
    // source of icons (they are covered in the nameOfIconFile and customIconForURL)
    // if their icons don't exist
    ABBindingClass class = ABBindingGetBindingClass(destination);
    BOOL sidebar = ABBindingIsSidebarVariant(destination);
    NSURL *customURL = customIconForURL(url);
    
    if (class == ABBindingClassBundle && !customURL)
        customURL = iconForBundle([NSBundle bundleWithURL:(__bridge NSURL *)(ABBundleBindingGetURL(destination))]);
    
    if (class != ABBindingClassBundle &&
        class != ABBindingClassSideFault &&
        class != ABBindingClassCustom &&
        class != ABBindingClassVolume &&
        !customURL) {
        
        // ABBindingCopyUTI doesnt follow the create rule despite its name
        NSString *uti = (__bridge NSString *)(ABBindingCopyUTI(destination));
        if (uti && UTTypeIsDynamic((__bridge CFStringRef)(uti)))
            uti = nil;
        
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
                                               0);
            }
            
            // Getting an OS Type off of the path for dirs breaks
            // so use the folder OS Type if this is an unidentifiable directory
            if ((ostype == 0 || ostype == '????') && url && !uti && class != ABBindingClassBundle) {
                // Dont apply the generic folder icon to packages
                // See if its a dir with a weird extension
                LSItemInfoRecord info;
                LSCopyItemInfoForURL((__bridge CFURLRef)url, kLSRequestBasicFlagsOnly, &info);
                if (info.flags & kLSItemInfoIsPackage)
                    ostype = kGenericExtensionIcon;
                else if (info.flags & kLSItemInfoIsContainer)
                    ostype = kGenericFolderIcon;
            }
            
            if (ostype != 0 && ostype != '????')
                customURL = customIconForOSType(ABStringFromOSType(ostype));
        }
        
    }
    
    if (customURL) {
        ABBindingRef custom = CreateWithResourceURL((__bridge CFURLRef)customURL, YES);
        
        // hax
        if (class != ABBindingClassBundle)
            ABBindingSetIconRef(destination, ABBindingGetIconRef(custom));
        else
            ABBindingOverride(destination, custom);
    }
    
    return destination;
}

#pragma mark - ABBinding
static UInt32 ABBindingGetMagic(ABBindingRef binding) {
    if (!binding)
        return 0;
    
    return *((UInt32 *)binding);
}

// Gets UTI associated with a binding
// + 0x80 is UTI function
// + 0x48 is OS Type
// + 0x40 on Bundle binding is the URL
static CFStringRef ABBindingCopyUTI(ABBindingRef arg0) {
    void *deref = *(void **)arg0;
    
    // big hax to call C++ instance method from C
    CFStringRef (*copyUTI)(ABBindingRef binding);
    copyUTI = *(void **)((uint8_t *)deref + 0x80);
    return copyUTI(arg0);
}

static UInt32 ABBindingGetOSType(ABBindingRef binding) {
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
    if (binding && IsValidIconRef(icon))
        *(IconRef *)((uint8_t *)binding + 0x8) = icon;
}

static ABBindingClass ABBindingGetBindingClass(ABBindingRef binding) {
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

#pragma mark - Class-Specific

static CFStringRef ABFileInfoBindingGetExtension(ABBindingRef binding) {
    if (ABBindingGetBindingClass(binding) == ABBindingClassFileInfo)
        return *(CFStringRef *)((uint8_t *)binding + 0x40);
    return NULL;
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

#define ABLogBinding(BINDING) ABLog("%@ [%p]", ABBindingGetDescription(BINDING), BINDING);
static CFStringRef ABBindingGetDescription(ABBindingRef binding) {
    void *deref = *(void **)binding;
    
    CFStringRef (*getDesc)(ABBindingRef binding);
    getDesc = *(void **)((uint8_t *)deref + 0x48);
    return getDesc(binding);
}

NSString *ABStringFromOSType(OSType type) {
    return (__bridge_transfer NSString *)UTCreateStringForOSType(type);
}
