//
//  ABLogging.h
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#ifndef AutumnBoard_ABLogging_h
#define AutumnBoard_ABLogging_h

#import "AutumnBoard.h"

#define OPLogLevelNotice LOG_NOTICE
#define OPLogLevelWarning LOG_WARNING
#define OPLogLevelError LOG_ERR

#include <syslog.h>

#define OPLog(level, format, ...) do { \
CFStringRef _formatted = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR(format), ## __VA_ARGS__); \
size_t _size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(_formatted), kCFStringEncodingUTF8); \
char _utf8[_size + sizeof('\0')]; \
CFStringGetCString(_formatted, _utf8, sizeof(_utf8), kCFStringEncodingUTF8); \
CFRelease(_formatted); \
syslog(level, "%s", _utf8); \
} while (false)

#define ABLog(FORMAT, ...) OPLog(OPLogLevelNotice, "AutumnBoard: " FORMAT, ## __VA_ARGS__)
#define ABLogBinding(BINDING) ABLog("%@ [%p]", ABBindingCopyDescription(BINDING), BINDING);

#endif
