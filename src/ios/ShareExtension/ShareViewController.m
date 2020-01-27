//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"

@interface ShareViewController : SLComposeServiceViewController {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic,retain) NSString *backURL;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) setup {
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    [self debug:@"[setup]"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {

    SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

    UIResponder* responder = self;
    while ((responder = [responder nextResponder]) != nil) {
        NSLog(@"responder = %@", responder);
        if([responder respondsToSelector:selector] == true) {
            NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

            // Arguments
            void (^completion)(BOOL success) = ^void(BOOL success) {
                NSLog(@"Completions block: %i", success);
            };
            if (@available(iOS 13.0, *)) {
                UISceneOpenExternalURLOptions * options = [[UISceneOpenExternalURLOptions alloc] init];
                options.universalLinksOnly = false;
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            } else {
                NSDictionary<NSString *, id> *options = [NSDictionary dictionary];
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            }
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setup];
}

- (void)viewDidAppear:(BOOL)animated {
    [self.view endEditing:YES];
    [self pickUpSelectedPost];
}

- (void)pickUpSelectedPost {
    [self debug:@"[didSelectPost]"];
    __block BOOL isFinished = NO;
    // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {
        
        NSArray *utis = [SHAREEXT_UNIFORM_TYPE_IDENTIFIER componentsSeparatedByString:@","];
        
        for (NSString *uti in utis) {
            
            if ([itemProvider hasItemConformingToTypeIdentifier:uti]) {
                [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];
                
                [itemProvider loadItemForTypeIdentifier:uti options:nil completionHandler: ^(id<NSSecureCoding> item, NSError *error) {
                    
                    NSData *data = [[NSData alloc] init];
                    if([(NSObject*)item isKindOfClass:[NSURL class]]) {
                        data = [NSData dataWithContentsOfURL:(NSURL*)item];
                    }
                    if([(NSObject*)item isKindOfClass:[UIImage class]]) {
                        data = UIImagePNGRepresentation((UIImage*)item);
                    }
                    if ([(NSObject *)item isKindOfClass:[NSData class]]) {
                        data = [NSData dataWithData:(NSData *)item];
                    }
                    
                    NSString *suggestedName = @"";
                    if ([(NSObject*)item isKindOfClass:[NSURL class]]) {
                        suggestedName = [[(NSURL*)item absoluteString] lastPathComponent];
                    } else if ([itemProvider respondsToSelector:NSSelectorFromString(@"getSuggestedName")]) {
                        suggestedName = [itemProvider valueForKey:@"suggestedName"];
                    }
                                        
                    NSString *uti = @"";
                    NSArray<NSString *> *utis = [NSArray new];
                    if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                        uti = itemProvider.registeredTypeIdentifiers[0];
                        utis = itemProvider.registeredTypeIdentifiers;
                    }
                    else {
                        uti = SHAREEXT_UNIFORM_TYPE_IDENTIFIER;
                    }
                    
                    void (^finishWithSuggestedName)(NSString *) = ^(NSString *theSuggestedName){
                     
                        NSURL *containerUrl = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER];
                        NSString *documentsPath = containerUrl.path;
                        NSTimeInterval stamp = [[NSDate date] timeIntervalSince1970];
                        NSString *filename = [theSuggestedName stringByAppendingFormat:@".%.0f", stamp];
                        NSString *filePath = [documentsPath stringByAppendingPathComponent: filename];
                        [data writeToFile:filePath atomically: YES];
                        
                        NSDictionary *dict = @{
                            @"text": self.contentText,
                            @"backURL": self.backURL,
                            // @"data" : data,
                            @"filename": filename,
                            @"uti": uti,
                            @"utis": utis,
                            @"name": theSuggestedName
                        };
                        [self.userDefaults setObject:dict forKey:@"image"];
                                                
                        // Emit a URL that opens the cordova app
                        NSString *url = [NSString stringWithFormat:@"%@://image", SHAREEXT_URL_SCHEME];
                        
                        // Not allowed:
                        // [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
                        
                        // Crashes:
                        // [self.extensionContext openURL:[NSURL URLWithString:url] completionHandler:nil];
                        
                        // From https://stackoverflow.com/a/25750229/2343390
                        // Reported not to work since iOS 8.3
                        // NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
                        // [self.webView loadRequest:request];
                        
                        [self openURL:[NSURL URLWithString:url]];
                        isFinished = YES;
                        // Inform the host that we're done, so it un-blocks its UI.
                        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                        
                    };
                    
                    if (suggestedName != nil && [suggestedName length] > 0) {
                        finishWithSuggestedName(suggestedName);
                    } else {
                        // then load file representation and get file name from url
                        [itemProvider loadFileRepresentationForTypeIdentifier:uti completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                            if (url != nil) {
                                NSString *theName = [[[url absoluteString] lastPathComponent] stringByRemovingPercentEncoding];
                                finishWithSuggestedName(theName);
                            }
                        }];
                    }
                    
                }];
                
                return;
            }
        }
    }

    if (!isFinished) {
        // Inform the host that we're done, so it un-blocks its UI.
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    }
}

- (NSArray*) configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    return @[];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    // App Store - com.apple.AppStore
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    // Calculator - com.apple.calculator
    // Calendar - com.apple.mobilecal
    // Camera - com.apple.camera
    // Clock - com.apple.mobiletimer
    // Compass - com.apple.compass
    // Contacts - com.apple.MobileAddressBook
    // FaceTime - com.apple.facetime
    // Find Friends - com.apple.mobileme.fmf1
    // Find iPhone - com.apple.mobileme.fmip1
    // Game Center - com.apple.gamecenter
    // Health - com.apple.Health
    // iBooks - com.apple.iBooks
    // iTunes Store - com.apple.MobileStore
    // Mail - com.apple.mobilemail - message://
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    // Maps - com.apple.Maps - maps://
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    // Messages - com.apple.MobileSMS
    // Music - com.apple.Music
    // News - com.apple.news - applenews://
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    // Notes - com.apple.mobilenotes - mobilenotes://
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    // Phone - com.apple.mobilephone
    // Photos - com.apple.mobileslideshow
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    // Podcasts - com.apple.podcasts
    // Reminders - com.apple.reminders - x-apple-reminder://
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    // Safari - com.apple.mobilesafari
    // Settings - com.apple.Preferences
    // Stocks - com.apple.stocks
    // Tips - com.apple.tips
    // Videos - com.apple.videos - videos://
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    // Voice Memos - com.apple.VoiceMemos - voicememos://
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    // Wallet - com.apple.Passbook
    // Watch - com.apple.Bridge
    // Weather - com.apple.weather
    return @"";
}

// This is called at the point where the Post dialog is about to be shown.
// We use it to store the _hostBundleID
- (void) willMoveToParentViewController: (UIViewController*)parent {
    // Note: uncomment to enable comeback-redirect from app.
    // Not used in Vault12 so disabled
    // NSString *hostBundleID = [parent valueForKey:(@"_hostBundleID")];
    // self.backURL = [self backURLFromBundleID:hostBundleID];
    self.backURL = @"";
}

@end
