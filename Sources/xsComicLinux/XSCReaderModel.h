#pragma once

#include "XSCBase.h"
#include "XSCArchive.h"
#include "XSCImageStore.h"

typedef enum XSCReadingDirection {
    XSCReadingDirectionLTR = 0,
    XSCReadingDirectionRTL = 1,
} XSCReadingDirection;

typedef enum XSCPageMode {
    XSCPageModeSingle = 0,
    XSCPageModeDouble = 1,
} XSCPageMode;

typedef enum XSCPageTurnKey {
    XSCPageTurnKeyLeft = 0,
    XSCPageTurnKeyRight = 1,
} XSCPageTurnKey;

@class XSCReaderModel;

#if defined(__APPLE__)
__attribute__((objc_non_runtime_protocol))
#endif
@protocol XSCReaderModelDelegate
- (void)readerModelDidUpdateState:(XSCReaderModel *)model;
- (void)readerModel:(XSCReaderModel *)model
    displayLeftPage:(XSCOptDecodedPage)leftPage
          rightPage:(XSCOptDecodedPage)rightPage
       showEmptyCTA:(bool)showEmptyCTA
          isLoading:(bool)isLoading
         statusText:(XSCOptString)statusText;
@end

/*
 XSCReaderModel is the reader's main-thread control plane.

 It owns the active Optional(XSCBook *), archive-order page position, spread/
 direction presentation math, the 2-turn backward prefetch predictor, zero-hop
 synchronous cache-hit dispatch, 120 ms loading grace timer, and predictive
 adjacent-volume pre-warming.
 */
@interface XSCReaderModel : XSCObject

@property (nonatomic, weak) id<XSCReaderModelDelegate> delegate;
@property (nonatomic, readonly) XSCImageStore *imageStore;
@property (nonatomic, readonly) XSCOptBook book;
@property (nonatomic, readonly) size_t currentIndex;
@property (nonatomic, readonly) XSCReadingDirection direction;
@property (nonatomic, readonly) XSCPageMode pageMode;
@property (nonatomic, readonly) bool isLoading;
@property (nonatomic, readonly) XSCOptString errorMessage;
@property (nonatomic, readonly) uint8_t consecutiveBackwardTurns;

/// Visible page indices in visual left-to-right display order (respects LTR/RTL and Single/Double).
@property (nonatomic, readonly) XSCIndexList *visualPageIndices;
/// Human-readable page label e.g. "1 / 120" or "2-3 / 120".
@property (nonatomic, readonly) XSCString *pageIndicatorText;

- (instancetype)init;
- (instancetype)initWithImageStore:(XSCImageStore *)imageStore;

/// Cancels pending archive work before the app joins its background workers.
- (void)cancelBackgroundWork;

- (void)openPath:(const char *)path;
- (void)openPath:(const char *)path startAtEnd:(bool)startAtEnd;

- (void)turnPageForKey:(XSCPageTurnKey)key
   swapRTLPageTurnKeys:(bool)swapRTL
 continueAcrossVolumes:(bool)continueAcrossVolumes;

- (void)goForwardContinueAcrossVolumes:(bool)continueAcrossVolumes;
- (void)goBackwardContinueAcrossVolumes:(bool)continueAcrossVolumes;

/// 1-based page jump. Returns true if valid and applied.
- (bool)jumpToOneBasedPageNumber:(int64_t)pageNumber;

- (void)toggleDirection;
- (void)togglePageMode;

/// Pure helper exposed for deterministic unit testing of the 8-ahead / 2-behind + 2-turn backward predictor.
+ (XSCIndexList *)prefetchOrderForCurrentIndex:(size_t)currentIndex
                                     pageCount:(size_t)pageCount
                                      pageMode:(XSCPageMode)pageMode
                      consecutiveBackwardTurns:(uint8_t)backwardTurns;

@end
