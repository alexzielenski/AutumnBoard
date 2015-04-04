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

static UInt32 ABBindingGetMagic(ABBindingRef binding);
static CFStringRef ABBindingCopyUTI(ABBindingRef arg0);
static UInt32 ABBindingGetType(ABBindingRef binding);
static IconRef ABBindingGetIconRef(ABBindingRef binding);
static UInt64 ABBindingGetVariantFlags(ABBindingRef binding);
static bool ABBindingIsSidebarVariant(ABBindingRef binding);
static ABBindingRef ABBindingGetVariantBinding(ABBindingRef binding);
static void ABBindingOverride(ABBindingRef destination, ABBindingRef custom);
static CFStringRef ABBindingGetDescription(ABBindingRef binding);

// OSType, EXT, UTI, FLAGS
static uint32_t (*GetSidebarVariantType)(OSType type, CFStringRef extension, CFStringRef uti, UInt64 flags);
void *ABPairBindingsWithURL(void *destination, void *custom, NSURL *url) {
    if (GetSidebarVariantType == NULL) {
        GetSidebarVariantType = OPFindSymbol(NULL, "__Z21GetSidebarVariantTypejPK10__CFStringS1_y");
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

void *ABPairBindings(void *destination, void *custom) {
    return ABPairBindingsWithURL(destination, custom, NULL);
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

static UInt32 ABBindingGetType(ABBindingRef binding) {
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

static UInt64 ABBindingGetVariantFlags(ABBindingRef binding) {
    UInt64 (*getFlags)(ABBindingRef binding);
    // HEY GUYS LOOK AT ALL THESE CASTS!
    getFlags = *(void **)((uint8_t *)(*(void **)binding) + 0x60);
    return getFlags(binding);
}

static bool ABBindingIsSidebarVariant(ABBindingRef binding) {
    if (ABBindingGetVariantFlags(binding) == 0x6) {
        UInt32 flags = *(OSType *)((uint8_t *)binding + 0x48);
        return flags != 0;
    }
    
    return NO;
}

// also holds extension for FileInfoBinding
static ABBindingRef ABBindingGetVariantBinding(ABBindingRef binding) {
    return *(void **)((uint8_t *)binding + 0x40);
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

#define ABLogBinding(BINDING) ABLog("Binding: %p (%@)", BINDING, ABBindingGetDescription(BINDING));
static CFStringRef ABBindingGetDescription(ABBindingRef binding) {
    void *deref = *(void **)binding;
    
    CFStringRef (*getDesc)(ABBindingRef binding);
    getDesc = *(void **)((uint8_t *)deref + 0x48);
    return getDesc(binding);
}

NSString *ABStringFromOSType(OSType type) {
    return (__bridge_transfer NSString *)UTCreateStringForOSType(type);
}
