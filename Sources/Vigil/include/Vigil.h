//
//  Vigil.h
//  Vigil - Hardware-backed runtime integrity validation
//
//  Copyright (c) 2025 Vigil Contributors
//  Licensed under MIT License
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double VigilVersionNumber;
FOUNDATION_EXPORT const unsigned char VigilVersionString[];

#pragma mark - Result Types

typedef NS_ENUM(NSInteger, VigilResult) {
    VigilResultValid = 0,
    VigilResultTampered = 1,
    VigilResultTimeout = 2,
    VigilResultError = 3
};

typedef NS_ENUM(NSInteger, VigilValidatorStatus) {
    VigilValidatorStatusUnknown = 0,
    VigilValidatorStatusRunning = 1,
    VigilValidatorStatusNotRunning = 2,
    VigilValidatorStatusNotConfigured = 3
};

typedef NS_ENUM(NSInteger, VigilLogLevel) {
    VigilLogLevelNone = 0,
    VigilLogLevelError = 1,
    VigilLogLevelWarning = 2,
    VigilLogLevelInfo = 3,
    VigilLogLevelDebug = 4
};

FOUNDATION_EXPORT NSErrorDomain const VigilErrorDomain;
FOUNDATION_EXPORT NSTimeInterval const VigilDefaultTimeout;
FOUNDATION_EXPORT NSNotificationName const VigilValidationDidCompleteNotification;
FOUNDATION_EXPORT NSString *const VigilResultKey;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Main Interface

/**
 * Vigil - Hardware-backed runtime integrity validation.
 *
 * Vigil detects binary tampering, code injection, and runtime manipulation
 * using a two-process architecture with Secure Enclave cryptography.
 *
 * @code
 * [Vigil initializeWithCompletion:^(BOOL success, NSError *error) {
 *     if (success) {
 *         [Vigil validateWithCompletion:^(VigilResult result) {
 *             if (result != VigilResultValid) {
 *                 // Handle tampering
 *             }
 *         }];
 *     }
 * }];
 * @endcode
 */
@interface Vigil : NSObject

#pragma mark - Initialization

+ (void)initializeWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (BOOL)isInitialized;

#pragma mark - Validation

+ (void)validateWithCompletion:(void (^)(VigilResult result))completion;
+ (void)validateWithTimeout:(NSTimeInterval)timeout
                 completion:(void (^)(VigilResult result))completion;
+ (VigilResult)validateSync;

#pragma mark - Status

+ (VigilValidatorStatus)validatorStatus;

#pragma mark - Configuration

+ (void)setLogLevel:(VigilLogLevel)level;
+ (VigilLogLevel)logLevel;
+ (NSString *)version;

@end

NS_ASSUME_NONNULL_END
