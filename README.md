##### 前面把`RACSubscriber`和`RACPassthroughSubscriber`里面的每个方法全部分析了一遍，接下来通过信号的一次订阅过程，分析下这两个类的实际运用。

以下用到的完整测试用例在[这里](https://github.com/jianghui1/TestRACSubscriberAndRACPassthroughSubscriber)。

测试用例：

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
这里，首先通过`createSignal`方法创建了一个信号，然后对该信号进行了订阅，查看`subscribeNext:`方法的实现。

    - (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock {
    	NSCParameterAssert(nextBlock != NULL);
    	
    	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:NULL];
    	return [self subscribe:o];
    }
方法中创建了一个`RACSubscriber`对象，然后作为`subscribe:`的参数。

继续查看`subscribe:`方法：

    - (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
    	NSCParameterAssert(subscriber != nil);
    
    	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
    	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];
    
    	if (self.didSubscribe != NULL) {
    		RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
    			RACDisposable *innerDisposable = self.didSubscribe(subscriber);
    			[disposable addDisposable:innerDisposable];
    		}];
    
    		[disposable addDisposable:schedulingDisposable];
    	}
    	
    	return disposable;
    }
该方法中的步骤比较多，所以分步骤进行分析：
1. 首先创建了一个`RACCompoundDisposable`类型的对象，通过前面的文章可以知道一点`RACCompoundDisposable`的作用，就是处理多个清理工作。
2. 接下来对`subscriber`重新进行初始化操作，通过`RACPassthroughSubscriber`的方法创建了一个`RACPassthroughSubscriber`对象。注意，这里方法的参数分别是`subscriber` `self` `disposable`，所以`RACPassthroughSubscriber`对象拥有了之前创建的`RACSubscriber`对象用于实际事件的发送；拥有了上一步创建的`RACCompoundDisposable`对象，可以根据`RACCompoundDisposable`对象是否做了清理工作来决定信号的事件是否应该继续被发送。
3. 接下来是对`didSubscribe`的判断。看下`didSubscribe`到底是什么呢？
    
        + (RACSignal *)createSignal:(RACDisposable * (^)(id<RACSubscriber> subscriber))didSubscribe {
        	RACDynamicSignal *signal = [[self alloc] init];
        	signal->_didSubscribe = [didSubscribe copy];
        	return [signal setNameWithFormat:@"+createSignal:"];
        }
    `didSubscribe`其实就是`createSignal`方法中创建信号时的block块，所以此时进入`if`条件判断中，继续执行代码。
4. 通过`RACScheduler.subscriptionScheduler`获取一个调度器，其实也就是一个新的线程，然后将`didSubscribe`的执行放到这个线程中，同时获取到`didSubscribe`返回值，也就是一个清理对象(上面例子中，该对象为nil)，添加到第一步创建的`RACCompoundDisposable`对象当中。接着将调度器的任务返回的清理对象也添加到`RACCompoundDisposable`对象当中。最后将`RACCompoundDisposable`对象返回。所以，一旦外界调用这个`RACCompoundDisposable`对象的清理方法，所有涉及到的任务都会被清理掉。
***
接下来改造下例子：

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
可以看到，这里显式调用了`dispose`方法，所以会做清理工作。这里的`RACDisposable`其实是`RACCompoundDisposable`类型的，看下`RACCompoundDisposable`的`dispose`方法：

    - (void)dispose {
    	#if RACCompoundDisposableInlineCount
    	RACDisposable *inlineCopy[RACCompoundDisposableInlineCount];
    	#endif
    
    	CFArrayRef remainingDisposables = NULL;
    
    	OSSpinLockLock(&_spinLock);
    	{
    		_disposed = YES;
    
    		#if RACCompoundDisposableInlineCount
    		for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
    			inlineCopy[i] = _inlineDisposables[i];
    			_inlineDisposables[i] = nil;
    		}
    		#endif
    
    		remainingDisposables = _disposables;
    		_disposables = NULL;
    	}
    	OSSpinLockUnlock(&_spinLock);
    
    	#if RACCompoundDisposableInlineCount
    	// Dispose outside of the lock in case the compound disposable is used
    	// recursively.
    	for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
    		[inlineCopy[i] dispose];
    	}
    	#endif
    
    	if (remainingDisposables == NULL) return;
    
    	CFIndex count = CFArrayGetCount(remainingDisposables);
    	CFArrayApplyFunction(remainingDisposables, CFRangeMake(0, count), &disposeEach, NULL);
    	CFRelease(remainingDisposables);
    }
可以看到，通过循环遍历，使存储的清理对象逐个调用`dispose`方法，完成清理工作。

上面显式调用了清理对象的清理方法，可以做清理工作，那么，如果不调用，结果又如何呢？
***
接下来继续改造例子：

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
可以看到，这里没有调用`dispose`方法，也会做清理工作。为什么呢？

前面分析过`RACSubscriber`的方法，如下：

    - (id)init {
    	self = [super init];
    	if (self == nil) return nil;
    
    	@unsafeify(self);
    
    	RACDisposable *selfDisposable = [RACDisposable disposableWithBlock:^{
    		@strongify(self);
    
    		@synchronized (self) {
    			self.next = nil;
    			self.error = nil;
    			self.completed = nil;
    		}
    	}];
    
    	_disposable = [RACCompoundDisposable compoundDisposable];
    	[_disposable addDisposable:selfDisposable];
    
    	return self;
    }
    - (void)dealloc {
    	[self.disposable dispose];
    }
其实，在订阅信号创建`RACSubscriber`时，也会生成一个`RACCompoundDisposable`对象。

再看下`RACPassthroughSubscriber`中的方法：

    - (instancetype)initWithSubscriber:(id<RACSubscriber>)subscriber signal:(RACSignal *)signal disposable:(RACCompoundDisposable *)disposable {
    	NSCParameterAssert(subscriber != nil);
    
    	self = [super init];
    	if (self == nil) return nil;
    
    	_innerSubscriber = subscriber;
    	_signal = signal;
    	_disposable = disposable;
    
    	[self.innerSubscriber didSubscribeWithDisposable:self.disposable];
    	return self;
    }
通过`[self.innerSubscriber didSubscribeWithDisposable:self.disposable];`将`disposable`添加到`RACSubscriber`类的`RACCompoundDisposable`当中。根据`subscribe:`代码可以知道这里的`disposable`就是要返回的清理对象，也就是外界订阅信号的时候可以获取到的信号。

所以，也就是说这里的清理对象虽然返回给外界供调用者使用，但是在订阅者`RACSubscriber`内部也会保留。此时，`RACSubscriber`对象是个局部变量，随着方法作用域的结束，会进行释放。查看其`dealloc`方法可知，内部会调用`[self.disposable dispose];`完成清理工作。这也就是为什么没有显式调用也能够完成清理工作的原因。
***
前面说了信号事件的发送会根据清理对象是否已经做了清理工作。测试用例如下：

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
可以看到，外部清理对象一旦做了清理工作，便会终止信号的发送。

上面把`RACSubscriber`和`RACPassthroughSubscriber`在信号订阅过程中的作用分析完了，接下来会分析其他遵循`RACSubscriber`协议的类。
