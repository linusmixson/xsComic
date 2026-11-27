#pragma once

#include "XSCBase.h"
#include "XSCArchive.h"

/*
 XSCImageStore owns decoded comic pages on Linux:
   - Page-aligned pixel mappings owned by decoded pages.
   - 8-bit monochrome fast path and lossless RGBA8-to-L8 repacking.
   - Native Linux codecs (libjpeg-turbo, libpng, libwebp, giflib, libtiff,
     built-in BMP, plus libavif/libheif when available) with EXIF 1..8 parsing.
   - Bounded LRU cache (12 entries / 64 MiB default), request coalescing,
     negative cache, and 4-lane priority pthread decode pool (1 lane reserved
     for visible demand).
 */

typedef struct XSCSizeF {
    float width;
    float height;
} XSCSizeF;

/// Decoded page backed by a page-aligned pixel buffer (L8 grayscale or RGBA8 color).
@interface XSCDecodedPage : XSCObject

@property (nonatomic, readonly) const uint8_t *pixels;
@property (nonatomic, readonly) size_t pixelWidth;
@property (nonatomic, readonly) size_t pixelHeight;
@property (nonatomic, readonly) size_t bytesPerRow;
@property (nonatomic, readonly) uint32_t exifOrientation; // 1..8
@property (nonatomic, readonly) bool isGrayscale;         // true = L8 (1 Bpp), false = RGBA8 (4 Bpp)
@property (nonatomic, readonly) size_t byteCount;
@property (nonatomic, readonly) bool isAnimatedGIF;
@property (nonatomic, readonly) size_t gifFrameCount;
@property (nonatomic, readonly) XSCOptData gifData;

/// Effective display dimensions after EXIF orientation (swaps width/height for orientations 5..8).
@property (nonatomic, readonly) XSCSizeF orientedPixelSize;

/// Returns RGBA8 pixel pointer for animated GIF frame `frameIndex` (same dimensions as page).
- (const uint8_t *)gifFramePixelsAtIndex:(size_t)frameIndex outDelayMs:(uint32_t *)outDelayMs;

/// Returns the visible frame and the next change relative to playback start, or UINT64_MAX when done.
- (size_t)gifFrameAtElapsedMs:(uint64_t)elapsed nextChangeMs:(uint64_t *)nextChange;

@end

typedef Optional(XSCDecodedPage *) XSCOptDecodedPage;
typedef void (^XSCPageCompletion)(XSCOptDecodedPage page, bool failed);

/// Bounded, concurrent image decode store with a lock-protected synchronous fast path.
@interface XSCImageStore : XSCObject

@property (nonatomic, readonly) size_t maxEntryCount;
@property (nonatomic, readonly) size_t maxByteBudget;
@property (nonatomic, readonly) size_t currentEntryCount;
@property (nonatomic, readonly) size_t currentByteCount;

- (instancetype)init;
- (instancetype)initWithMaxEntryCount:(size_t)maxEntries maxByteBudget:(size_t)maxBytes;

/// Zero-hop synchronous cache lookup. Returns None on a miss.
- (XSCOptDecodedPage)cachedPageForBook:(XSCBook *)book index:(size_t)index;

/// Asynchronous decode request with coalescing and priority demand lane.
/// `completion` is ALWAYS invoked on the main queue via xsc_dispatch_main.
- (void)requestPageForBook:(XSCBook *)book
                     index:(size_t)index
                  priority:(bool)isVisible
                completion:(XSCPageCompletion)completion;

/// Sets eviction priority and prefetches `orderedIndices`, prioritizing `visibleIndices`.
- (void)updateRetentionAndPrefetchForBook:(XSCBook *)book
                           visibleIndices:(XSCIndexList *)visibleIndices
                           orderedIndices:(XSCIndexList *)orderedIndices;

/// Pre-decodes a single boundary page of an adjacent volume without evicting active visible pages.
- (void)prewarmPageForBook:(XSCBook *)book index:(size_t)index;

/// Cancels pending prefetch work and clears cached entries for books other than `keepBook` (or all if None).
- (void)resetKeepingBook:(XSCOptBook)keepBook;

/// Stops worker threads cleanly.
- (void)shutdown;

@end
