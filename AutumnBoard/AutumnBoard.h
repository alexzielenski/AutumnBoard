//
//  AutumnBoard.h
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/8/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#ifndef AutumnBoard_AutumnBoard_h
#define AutumnBoard_AutumnBoard_h

#import <Foundation/Foundation.h>

static NSString *const ABLaunchServicesVersion101003 = @"644.56";
static NSString *const ABLaunchServicesVersion101002 = @"644.12.4";

NSString *ABLaunchServicesVersion();
BOOL ABLaunchServicesVersionInRange(NSString *lower, NSString *upper); // inclusive
BOOL ABLaunchServicesVersionEquals(NSString *version);
BOOL ABIsSupportedVersion();

#endif
