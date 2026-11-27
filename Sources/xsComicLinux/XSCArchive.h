#pragma once

#include "XSCBase.h"

/*
 XSCArchive owns the boundary between xsComic and the Linux filesystem/archives.

 Design principles:
   1. Minimal system dependencies — POSIX, zlib (-lz), and libarchive (-larchive).
   2. Zero upfront disk extraction for CBZ/ZIP and CBT/TAR — opening parses only
      the Central Directory or 512-byte TAR headers via stateless pread(2), so
      even a 500-page volume opens in ~1 ms with zero disk writes.
   3. In-process streaming for CBR/RAR4/RAR5/CB7/7z — keeps archives <= 256 MiB
      in RAM and spills larger archives to a private per-process temp directory
      cleaned by both -dealloc and atexit(3).
   4. Immutable, lock-free thread safety — once +openPath:cancelFlag: returns
      an XSCBook, its entry table and byte arena never mutate, and
      readPageDataAtIndex: may be called concurrently from any decode thread.
   5. Idiomatic Objective-C 3.0 — typed throws(XSCError *), Optional(XSCString *),
      Result, exhaustive match, and defer cleanup.
 */

typedef enum XSCArchiveErrorCode {
    XSCArchiveErrorMissingFile = 1,
    XSCArchiveErrorUnsupportedFormat = 2,
    XSCArchiveErrorNoImages = 3,
    XSCArchiveErrorCorruptArchive = 4,
    XSCArchiveErrorUnsafePath = 5,
    XSCArchiveErrorEncrypted = 6,
    XSCArchiveErrorCancelled = 7,
    XSCArchiveErrorIOFailure = 8,
    XSCArchiveErrorResourceLimit = 9,
} XSCArchiveErrorCode;

typedef enum XSCComparisonResult {
    XSCOrderedAscending = -1,
    XSCOrderedSame = 0,
    XSCOrderedDescending = 1,
} XSCComparisonResult;

/// Immutable, thread-safe representation of an opened comic book (directory, CBZ, CBT, CBR, CB7).
@interface XSCBook : XSCObject

@property (nonatomic, readonly) XSCString *sourcePath;
@property (nonatomic, readonly) XSCString *displayTitle;
@property (nonatomic, readonly) size_t pageCount;
/// Process-wide monotonically increasing identifier used as part of cache keys in XSCImageStore.
@property (nonatomic, readonly) uint64_t bookID;

+ (bool)isSupportedArchiveExtension:(const char *)ext;
+ (bool)isSupportedImageExtension:(const char *)ext;

/// Zero-allocation ASCII-fast natural comparison ("2" before "10", case-insensitive,
/// with deterministic raw-byte tie-breaking) and UTF-8 aware numeric sorting.
+ (XSCComparisonResult)naturalCompareBytes:(const char *)a
                                    length:(size_t)aLen
                                 withBytes:(const char *)b
                                    length:(size_t)bLen;

/// Opens a directory or archive file. Safe to call off the main thread.
/// If `cancelFlag` becomes true, throws XSCError with XSCArchiveErrorCancelled.
+ (XSCBook *)openPath:(const char *)path
           cancelFlag:(const _Atomic(bool) *)cancelFlag throws(XSCError *);

/// Finds the next (+1) or previous (-1) readable sibling archive or image directory in natural order.
+ (XSCOptString)adjacentVolumePathFor:(const char *)currentPath
                                 step:(int)step
                           cancelFlag:(const _Atomic(bool) *)cancelFlag;

/// Returns the display name (relative path or filename) of page at `index`.
- (XSCString *)pageNameAtIndex:(size_t)index;

/// Returns true if the page at `index` has a `.gif` extension.
- (bool)isGIFAtIndex:(size_t)index;

/// Thread-safe random-access read of raw encoded image bytes for page `index`.
- (XSCData *)readPageDataAtIndex:(size_t)index throws(XSCError *);

@end

typedef Optional(XSCBook *) XSCOptBook;
typedef Result(XSCBook *, XSCError *) XSCBookResult;
