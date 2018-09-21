/*
 * Copyright © 2016 Intel Corporation. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <AFNetworking/AFNetworking.h>
#import <ICS/ICS.h>
#import "ConferenceConnectionViewController.h"
#import "AppDelegate.h"
#import "HorizontalSegue.h"

@interface ConferenceConnectionViewController ()

-(void)getTokenFromBasicSample:(NSString *)basicServer onSuccess:(void (^)(NSString *))onSuccess onFailure:(void (^)())onFailure;

@property (nonatomic) ICSConferenceClient* conferenceClient;

@end

@implementation ConferenceConnectionViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor clearColor];
  self.hostTb.delegate=self;
  AppDelegate* appDelegate = (id)[[UIApplication sharedApplication]delegate];
  _conferenceClient=[appDelegate conferenceClient];
  NSString *tmpStr = [[NSUserDefaults standardUserDefaults] stringForKey:@"userDefaultURL"];
  if (tmpStr && tmpStr.length != 0) {
    [_hostTb setText: tmpStr];
  }
  // Socket.IO library uese low level network APIs. In some iOS 10 devices, OS does not ask user for network permission. As a result, Socket.IO connection fails because app does not have network access. Following code uese Objective-C API to trigger a network request, so user will have the chance to allow network permission for this app.
  NSMutableURLRequest *request=[[NSMutableURLRequest alloc]init];
  [request setURL:[NSURL URLWithString:@"https://www.apple.com"]];
  NSOperationQueue *queue = [[NSOperationQueue alloc] init];
  [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
    // Nothing here.
  }];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}


-(BOOL)textFieldShouldReturn:(UITextField *)textField{
  [self.hostTb resignFirstResponder];
  return YES;
}


-(void)getTokenFromBasicSample:(NSString *)basicServer onSuccess:(void (^)(NSString *))onSuccess onFailure:(void (^)())onFailure{
  AppDelegate* appDelegate = (AppDelegate*)[[UIApplication sharedApplication]delegate];
  appDelegate.serverUrl=basicServer;
  AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
  manager.requestSerializer = [AFJSONRequestSerializer serializer];
  [manager.requestSerializer setValue:@"*/*" forHTTPHeaderField:@"Accept"];
  [manager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  manager.responseSerializer = [AFHTTPResponseSerializer serializer];
  manager.securityPolicy.allowInvalidCertificates=NO;
  manager.securityPolicy.validatesDomainName=YES;
  NSDictionary *params = [[NSDictionary alloc]initWithObjectsAndKeys:@"", @"room", @"user", @"username", @"presenter", @"role", nil];
  [manager POST:[basicServer stringByAppendingString:@"createToken/"] parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
    NSData* data=[[NSData alloc]initWithData:responseObject];
    onSuccess([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]);
  } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
    NSLog(@"Error: %@", error);
  }];
}

- (IBAction)connectBtnTouchDown:(id)sender {
  [[NSUserDefaults standardUserDefaults] setValue:_hostTb.text forKey:@"userDefaultURL"];
  [self getTokenFromBasicSample:_hostTb.text onSuccess:^(NSString *token) {
    [_conferenceClient joinWithToken:token onSuccess:^(ICSConferenceInfo* info) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if([info.remoteStreams count]>0){
          AppDelegate* appDelegate = (AppDelegate*)[[UIApplication sharedApplication]delegate];
          appDelegate.conferenceId=info.conferenceId;
          for(ICSRemoteStream* s in info.remoteStreams){
            s.delegate=appDelegate;
            if([s isKindOfClass:[ICSRemoteMixedStream class]]){
              appDelegate.mixedStream=(ICSRemoteMixedStream*)s;
              break;
            }
          }
        }
        [self performSegueWithIdentifier:@"Login" sender:self];
      });
    } onFailure:^(NSError* err) {
      NSLog(@"Join failed. %@", err);
    }];
  } onFailure:^{
    NSLog(@"Failed to get token from basic server.");
  }];
  
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
  HorizontalSegue *s = (HorizontalSegue *)segue;
  s.isDismiss = NO;
}


@end
