#pragma once

#if defined(__APPLE__)
#include <objc3_darwin.h>
#else
#include <objc/runtime.h>
#endif
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef nil
#define nil ((id)0)
#endif

#if defined(__has_include) && __has_include(<objc3/core.h>)
#include <objc3/core.h>
#endif

#if defined(__has_include) && __has_include(<objc3/errors.h>)
#include <objc3/errors.h>
#else
#if defined(__APPLE__)
__attribute__((objc_non_runtime_protocol))
#endif
@protocol Error
@end
#endif

/*
 XSCBase provides a tiny, zero-bloat Objective-C 3.0 foundation layer on top of
 the platform's owned Objective-C runtime and POSIX pthreads. Avoiding GNUstep-Base keeps the
 executable small, launch time fast, and memory ownership explicit.
 */

__attribute__((objc_root_class))
@interface XSCObject {
    Class isa;
}
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
- (void)dealloc;
@end

/// Immutable, NUL-terminated UTF-8 string owned under ARC.
@interface XSCString : XSCObject
@property (nonatomic, readonly) const char *utf8;
@property (nonatomic, readonly) size_t length;

+ (instancetype)emptyString;
+ (instancetype)stringWithUTF8:(const char *)utf8;
+ (instancetype)stringWithBytes:(const char *)bytes length:(size_t)length;
+ (instancetype)stringWithFormat:(const char *)fmt, ... __attribute__((format(printf, 1, 2)));

- (bool)isEqualToString:(XSCString *)other;
- (bool)isEqualToUTF8:(const char *)utf8;
- (bool)hasPrefixUTF8:(const char *)prefix;
- (bool)hasSuffixUTF8:(const char *)suffix;
- (XSCString *)lastPathComponent;
- (XSCString *)stringByDeletingLastPathComponent;
- (XSCString *)stringByAppendingPathComponent:(const char *)component;
@end

/// Immutable owned byte buffer.
@interface XSCData : XSCObject
@property (nonatomic, readonly) const uint8_t *bytes;
@property (nonatomic, readonly) size_t length;

+ (instancetype)emptyData;
+ (instancetype)dataWithBytes:(const void *)bytes length:(size_t)length;
/// Takes ownership of a malloc()-allocated buffer and frees it in -dealloc.
+ (instancetype)dataTakingBytesNoCopy:(void *)bytes length:(size_t)length;

- (bool)isEqualToData:(XSCData *)other;
@end

typedef enum XSCErrorDomain {
    XSCErrorDomainArchive = 1,
    XSCErrorDomainImage = 2,
    XSCErrorDomainUI = 3,
} XSCErrorDomain;

/// Typed error object conforming to Objective-C 3.0's Error protocol.
@interface XSCError : XSCObject <Error>
@property (nonatomic, readonly) XSCErrorDomain domain;
@property (nonatomic, readonly) int code;
@property (nonatomic, readonly) XSCString *message;

+ (instancetype)errorWithDomain:(XSCErrorDomain)domain code:(int)code message:(const char *)utf8;
+ (instancetype)errorWithDomain:(XSCErrorDomain)domain code:(int)code string:(XSCString *)message;
@end

/// Compact immutable array of page indices (replaces NSArray<NSNumber *> / NSIndexSet).
@interface XSCIndexList : XSCObject
@property (nonatomic, readonly) size_t count;
@property (nonatomic, readonly) const size_t *values;

+ (instancetype)emptyList;
+ (instancetype)listWithValues:(const size_t *)values count:(size_t)count;
- (size_t)valueAtIndex:(size_t)index;
- (bool)containsValue:(size_t)value;
@end

// Shared Objective-C 3.0 carrier aliases
typedef Optional(XSCString *) XSCOptString;
typedef Optional(XSCData *) XSCOptData;
typedef Optional(size_t) XSCOptIndex;
typedef void (^XSCVoidBlock)(void);

// Monotonic clock
uint64_t xsc_now_ns(void);
double xsc_now_ms(void);

// Main-thread queue & timed dispatch (drives both SDL2 event loop and headless tests)
void xsc_mark_main_thread(void);
bool xsc_is_main_thread(void);
void xsc_set_main_wakeup(void (*wakeup_fn)(void));
void xsc_dispatch_main(XSCVoidBlock block);
void xsc_dispatch_main_after_ms(uint64_t delay_ms, XSCVoidBlock block);
size_t xsc_main_drain(void);
bool xsc_main_wait_ms(uint64_t timeout_ms);
/// Monotonic wakeup time for queued main work, or UINT64_MAX when idle.
uint64_t xsc_main_next_deadline_ms(void);

// Background work dispatch (replaces GCD global concurrent queues)
void xsc_dispatch_bg(XSCVoidBlock block);
void xsc_dispatch_bg_shutdown(void);

// Recursive POSIX file/directory removal helper
void xsc_remove_tree(const char *path);
