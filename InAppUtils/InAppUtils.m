#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
    NSMutableArray *_transactions;
    NSString *_purchaseIdentifier;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
        _transactions = [NSMutableArray array];
        _purchaseIdentifier = @"";
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[
             @"updatedDownloads"
             ];
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
    for (SKDownload *download in downloads)
    {
        float _prog = -1;
        float _time = -1;
        float _dlStatus = -1;
        NSString *_completeMsg = @"";
        NSString *_identifier = download.contentIdentifier;
        
        switch (download.downloadState) {
                
            case SKDownloadStateActive:
                NSLog(@"Download progress = %f",
                      download.progress);
                NSLog(@"Download time = %f",
                      download.timeRemaining);
                
                _prog = download.progress;
                _time = download.timeRemaining;
                _dlStatus = 1;
                
                break;
            case SKDownloadStateWaiting:
                _prog = 0;
                _time = 0;
                _completeMsg = @"download waiting...";
                _dlStatus = 0;
                break;
            case SKDownloadStateFailed:
                NSLog(@"Transaction error: %@", download.transaction.error.localizedDescription);
                
                _prog = 0;
                _time = 0;
                _completeMsg = @"download failed...";
                _completeMsg = [_completeMsg stringByAppendingString:download.transaction.error.localizedDescription];
                _dlStatus = -100;
                //finish the transaction
                //[[SKPaymentQueue defaultQueue] finishTransaction:download.transaction];
                [self completeTransaction:download.transaction];
                break;
            case SKDownloadStateFinished:
            {
                
                NSLog(@"URL %@",download.contentURL);
                _prog = 0;
                _time = 0;
                _dlStatus = 100;
                if(download.contentURL==nil) {
                    _completeMsg = @"download complete - no content URL supplied";
                }
                else {
                    _completeMsg = [download.contentURL absoluteString];
                }
            }
                
                break;
            default:
                break;
        }
        
        
        if([_completeMsg length]>0) {
            NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
            [event setObject:(NSString *)_completeMsg forKey:@"complete"];
            [event setObject:[NSString stringWithFormat:@"%@", _identifier] forKey:@"identifier"];
            [event setObject:[NSString stringWithFormat:@"%f", _dlStatus] forKey:@"dlStatus"];
            
            [self sendEventWithName:@"updatedDownloads" body:event];
        }
        else {
            NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
            [event setObject:[NSString stringWithFormat:@"%f", _prog] forKey:@"progress"];
            [event setObject:[NSString stringWithFormat:@"%f", _time] forKey:@"timeRemaining"];
            [event setObject:[NSString stringWithFormat:@"%@", _identifier] forKey:@"identifier"];
            [event setObject:[NSString stringWithFormat:@"%f", _dlStatus] forKey:@"dlStatus"];
            
            [self sendEventWithName:@"updatedDownloads" body:event];
        }
    }
    
    //emit an event back to JS
}

RCT_EXPORT_MODULE()
- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        NSString *thisID = transaction.payment.productIdentifier;
        BOOL isSelectedPlan = false;
        NSLog(@"%d", [thisID isEqualToString:_purchaseIdentifier]);
        if([thisID isEqualToString:_purchaseIdentifier] == 1){
            isSelectedPlan = true;
        }
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    callback(@[RCTJSErrorFromNSError(transaction.error)]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state failed.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                //[self failedTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                
                
                
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    NSDictionary *purchase = @{
                                               @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                                               @"transactionIdentifier": transaction.transactionIdentifier,
                                               @"productIdentifier": transaction.payment.productIdentifier,
                                               @"transactionReceipt": [[transaction transactionReceipt] base64EncodedStringWithOptions:0]
                                               };
                    callback(@[[NSNull null], purchase]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state purchased.");
                }
                /*if(isSelectedPlan){
                    if(transaction.downloads){
                        [self download:transaction];
                    }else{
                        //[[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                        [self completeTransaction:transaction];
                    }
                }else{
                    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                }*/

                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStateRestored:
                
                if(isSelectedPlan){
                    if(transaction.downloads)
                        [self restoreDownload:transaction];
                    else
                        [self restoreTransaction:transaction];
                    break;
                }else{
                    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                }
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"purchasing");
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"deferred");
                break;
            default:
                break;
        }
    }
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    NSLog(@"completeTransaction...");
    
    [self provideContentForProductIdentifier:transaction.payment.productIdentifier];
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}


- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    NSLog(@"restoreTransaction...");
    
    
    [self  provideContentForProductIdentifier:transaction.originalTransaction.payment.productIdentifier];
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)restoreDownload:(SKPaymentTransaction *)transaction {
    NSLog(@"restoreDownload...");
    
    //[self validateReceiptForTransaction:transaction];
    [self provideContentForProductIdentifier:transaction.originalTransaction.payment.productIdentifier];
    
    [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
    
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {
    
    NSLog(@"failedTransaction...");
    if (transaction.error.code != SKErrorPaymentCancelled)
    {
        NSLog(@"Transaction error: %@", transaction.error.localizedDescription);
    }
    
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)download:(SKPaymentTransaction *)transaction {
    NSLog(@"Download Content...");
    
    [self provideContentForProductIdentifier:transaction.payment.productIdentifier];
    [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
    //[[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}
- (void)doDownloadForProductIdentifier:(NSString *)productIdentifier
                              callback:(RCTResponseSenderBlock)callback
{
    NSLog(@"Download Content By ProductID...");
    BOOL hasFoundProduct = false;
    for(SKPaymentTransaction *transaction in _transactions){
        if(!hasFoundProduct){
            //if(transaction.payment.productIdentifier == productIdentifier){
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {
                hasFoundProduct = true;
                [self provideContentForProductIdentifier:productIdentifier];
                [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
            }
            //}
        }
    }
    callback(@[@(hasFoundProduct)]);
    //[[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)provideContentForProductIdentifier:(NSString *)productIdentifier {
    
    //[_purchasedProductIdentifiers addObject:productIdentifier];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:productIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
}
RCT_EXPORT_METHOD(downloadForProductIdentifier:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doDownloadForProductIdentifier:productIdentifier callback:callback];
}

RCT_EXPORT_METHOD(purchaseProductForUser:(NSString *)productIdentifier
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier username:username callback:callback];
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier username:nil callback:callback];
}

- (void) doPurchaseProduct:(NSString *)productIdentifier
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback
{
    SKProduct *product;
    _purchaseIdentifier = productIdentifier;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }
    
    if(product) {
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
        if(username) {
            payment.applicationUsername = username;
        }
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        switch (error.code)
        {
            case SKErrorPaymentCancelled:
                callback(@[@"user_cancelled"]);
                break;
            default:
                callback(@[@"restore_failed"]);
                break;
        }
        
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    //_transactions = [queue copy];
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        [_transactions removeAllObjects];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKPaymentTransaction *transaction in queue.transactions){
            //_transactions.push(transaction);
            [_transactions addObject: transaction];
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {
                
                NSMutableDictionary *purchase = [NSMutableDictionary dictionaryWithDictionary: @{
                                                                                                 @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                                                                                                 @"transactionIdentifier": transaction.transactionIdentifier,
                                                                                                 @"productIdentifier": transaction.payment.productIdentifier,
                                                                                                 @"transactionReceipt": [[transaction transactionReceipt] base64EncodedStringWithOptions:0]
                                                                                                 }];
                
                SKPaymentTransaction *originalTransaction = transaction.originalTransaction;
                if (originalTransaction) {
                    purchase[@"originalTransactionDate"] = @(originalTransaction.transactionDate.timeIntervalSince1970 * 1000);
                    purchase[@"originalTransactionIdentifier"] = originalTransaction.transactionIdentifier;
                }
                
                [productsArrayForJS addObject:purchase];
                //[[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                //[self completeTransaction:transaction];       //This call interrupts the downloads on a restore.
            }
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _purchaseIdentifier = @"";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}
RCT_EXPORT_METHOD(restorePurchaseForIdentifier:(NSString *)identifier
                  callback:(RCTResponseSenderBlock)callback)
{
    _purchaseIdentifier = identifier;
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(restorePurchasesForUser:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    if(!username) {
        callback(@[@"username_required"]);
        return;
    }
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactionsWithApplicationUsername:username];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                          initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
    productsRequest.delegate = self;
    _callbacks[RCTKeyForInstance(productsRequest)] = callback;
    [productsRequest start];
}

RCT_EXPORT_METHOD(canMakePayments: (RCTResponseSenderBlock)callback)
{
    BOOL canMakePayments = [SKPaymentQueue canMakePayments];
    callback(@[@(canMakePayments)]);
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
        callback(@[@"not_available"]);
    } else {
        callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"countryCode": [item.priceLocale objectForKey: NSLocaleCountryCode],
                                      @"downloadable": item.downloadable ? @"true" : @"false" ,
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      };
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

// SKProductsRequestDelegate network error
/*- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
 NSString *key = RCTKeyForInstance(request);
 RCTResponseSenderBlock callback = _callbacks[key];
 if(callback) {
 callback(@[RCTJSErrorFromNSError(error)]);
 [_callbacks removeObjectForKey:key];
 }
 }*/
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        // Ensure error.userData can be converted to JSON without error.
        // This will remove any NSURL from the error.userData.
        error = RCTErrorClean(error);
        callback(@[RCTJSErrorFromNSError(error)]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for request error.");
    }
}



- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

static NSError *RCTErrorClean(NSError *error)
{
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [RCTJSONClean(error.userInfo) enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && ![value isKindOfClass:NSNull.class]) {
            userInfo[key] = value;
        }
    }];
    
    return [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
}

@end

