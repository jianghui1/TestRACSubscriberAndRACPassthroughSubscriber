//
//  TestRACSubscriberAndRACPassthroughSubscriberTests.m
//  TestRACSubscriberAndRACPassthroughSubscriberTests
//
//  Created by ys on 2018/8/22.
//  Copyright © 2018年 ys. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <ReactiveCocoa.h>

@interface TestRACSubscriberAndRACPassthroughSubscriberTests : XCTestCase

@end

@implementation TestRACSubscriberAndRACPassthroughSubscriberTests

- (RACSignal *)createSignal
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@(1)];
        [subscriber sendCompleted];
        
        return nil;
    }];
}

- (void)testSubscriber
{
    [[self createSignal]
     subscribeNext:^(id x) {
         NSLog(@"subscriber -- %@", x);
     }];
    
    // 打印日志；
    /*
     2018-08-22 17:12:40.849495+0800 TestRACSubscriberAndRACPassthroughSubscriber[41242:3744055] subscriber -- 1
     */
}

- (RACSignal *)createSignal1
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@(1)];
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"woguale");
        }];
    }];
}

- (void)testSubscriber1
{
    RACDisposable *disposable = [[self createSignal1]
                                 subscribeNext:^(id x) {
                                     NSLog(@"subscriber -- %@", x);
                                 }];
    [disposable dispose];
    // 打印日志；
    /*
     2018-08-22 18:05:48.451933+0800 TestRACSubscriberAndRACPassthroughSubscriber[3006:75065] subscriber -- 1
     2018-08-22 18:05:48.452257+0800 TestRACSubscriberAndRACPassthroughSubscriber[3006:75065] woguale
     */
}

- (RACSignal *)createSignal2
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@(1)];
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"woguale");
        }];
    }];
}

- (void)testSubscriber2
{
    [[self createSignal2]
     subscribeNext:^(id x) {
         NSLog(@"subscriber -- %@", x);
     }];
    
    // 打印日志；
    /*
     2018-08-22 18:14:53.746384+0800 TestRACSubscriberAndRACPassthroughSubscriber[3310:100752] subscriber -- 1
     2018-08-22 18:14:53.746773+0800 TestRACSubscriberAndRACPassthroughSubscriber[3310:100752] woguale
     */
}

- (void)testSubscriber3
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [[RACScheduler scheduler] afterDelay:0.3 schedule:^{
            [subscriber sendNext:@(1)];
            [subscriber sendCompleted];
            
        }];
        
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"woguale");
        }];
    }];
    
    [signal subscribeNext:^(id x) {
        NSLog(@"signal");
    }];
    
    RACSignal *signal1 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [[RACScheduler scheduler] afterDelay:0.3 schedule:^{
            [subscriber sendNext:@(1)];
            [subscriber sendCompleted];
            
        }];
        
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"woguale1");
        }];
    }];
    
    RACDisposable *disposable = [signal1 subscribeNext:^(id x) {
        NSLog(@"signal1");
    }];
    [disposable dispose];
    
    [[RACSignal never] asynchronouslyWaitUntilCompleted:nil];
    
    // 打印日志：
    /*
     2018-08-22 18:50:47.630042+0800 TestRACSubscriberAndRACPassthroughSubscriber[4529:202051] woguale1
     2018-08-22 18:50:47.931631+0800 TestRACSubscriberAndRACPassthroughSubscriber[4529:202084] signal
     2018-08-22 18:50:47.932003+0800 TestRACSubscriberAndRACPassthroughSubscriber[4529:202084] woguale
     */
}

@end
