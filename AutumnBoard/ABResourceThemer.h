//
//  ABResourceThemer.h
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#ifndef __AutumnBoard__ABResourceThemer__
#define __AutumnBoard__ABResourceThemer__

#import <Foundation/Foundation.h>

NSURL *iconForBundle(NSBundle *bundle);
BOOL hasResourceForBundle(NSBundle *bundle, CFStringRef resource, CFStringRef resourceType, CFStringRef subDir, CFURLRef *resourceURL);
NSURL *replacementURLForURL(NSURL *url);
NSURL *replacementURLForURLRelativeToBundle(NSURL *url, NSBundle *bndl);

NSURL *customIconForURL(NSURL *url);
NSURL *customIconForOSType(NSString *type);
NSURL *customIconForUTI(NSString *uti);
NSURL *customIconForExtension(NSString *extension);

BOOL ABIsInQuicklook();

#endif /* defined(__AutumnBoard__ABResourceThemer__) */
