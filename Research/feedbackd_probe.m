#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@protocol FeedbackDaemonProtocolProbe
- (void)fetchCountsForFormWithIdentifier:(NSString *)identifier
                              completion:(void (^)(id count, NSError *error))completion;
- (void)clearCachedUserSessionWithCompletion:(void (^)(NSError *error))completion;
@end

@protocol FeedbackDaemonAdminProtocolProbe
- (void)reportFailureToLaunchFormWithFormIdentifier:(NSString *)identifier
                                         completion:(void (^)(NSError *error))completion;
- (void)didFinishSubmissionWithFormIdentifier:(NSString *)identifier
                                   feedbackId:(NSNumber *)feedbackId
                                     isSurvey:(BOOL)isSurvey
                                        error:(NSError *)error
                                   completion:(void (^)(NSError *error))completion;
@end

static void print_methods_for_class(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) {
        printf("class missing: %s\n", name);
        return;
    }

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    printf("class %s methods: %u\n", name, count);
    for (unsigned int i = 0; i < count; i++) {
        printf("  %s\n", sel_getName(method_getName(methods[i])));
    }
    free(methods);
}

static void print_methods_for_protocol(const char *name) {
    Protocol *protocol = objc_getProtocol(name);
    if (!protocol) {
        printf("protocol missing: %s\n", name);
        return;
    }

    unsigned int count = 0;
    struct objc_method_description *methods =
        protocol_copyMethodDescriptionList(protocol, YES, YES, &count);
    printf("protocol %s required instance methods: %u\n", name, count);
    for (unsigned int i = 0; i < count; i++) {
        printf("  %s %s\n", sel_getName(methods[i].name), methods[i].types ?: "");
    }
    free(methods);
}

static void inspect_runtime(void) {
    const char *service = "/System/Library/PrivateFrameworks/FeedbackService.framework/FeedbackService";
    void *serviceHandle = dlopen(service, RTLD_NOW);
    printf("dlopen FeedbackService: %s\n", serviceHandle ? "ok" : dlerror());

    const char *core = "/System/Library/PrivateFrameworks/FeedbackCore.framework/FeedbackCore";
    void *coreHandle = dlopen(core, RTLD_NOW);
    printf("dlopen FeedbackCore: %s\n", coreHandle ? "ok" : dlerror());

    print_methods_for_class("_TtC15FeedbackService23FeedbackDaemonInterface");
    print_methods_for_class("_TtC15FeedbackService28FeedbackDaemonAdminInterface");
    print_methods_for_class("_TtC15FeedbackService34CentralizedFeedbackDaemonInterface");

    print_methods_for_protocol("_TtP15FeedbackService22FeedbackDaemonProtocol_");
    print_methods_for_protocol("_TtP15FeedbackService27FeedbackDaemonAdminProtocol_");
    print_methods_for_protocol("_TtP15FeedbackService28FeedbackFilingDaemonProtocol_");
    print_methods_for_protocol("_TtP15FeedbackService33CentralizedFeedbackDaemonProtocol_");

    print_methods_for_class("FBKLaunchAction");
    print_methods_for_class("FBKData");
    print_methods_for_class("FBKSeedPortalAPI");
    print_methods_for_class("FBKDraftingController");
    print_methods_for_class("FBKFormResponse");
    print_methods_for_class("FBKBugFormStub");
    print_methods_for_class("FBKUploadTask");
}

static void probe_fetch_counts(NSString *formIdentifier) {
    NSXPCConnection *connection =
        [[NSXPCConnection alloc] initWithMachServiceName:@"com.apple.feedbackd.centralized-feedback"
                                                 options:0];
    connection.remoteObjectInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(FeedbackDaemonProtocolProbe)];
    [connection resume];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    id remote = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        NSLog(@"remote proxy error: %@", error);
        dispatch_semaphore_signal(sema);
    }];

    NSLog(@"calling fetchCountsForFormWithIdentifier:%@", formIdentifier);
    [remote fetchCountsForFormWithIdentifier:formIdentifier completion:^(id count, NSError *error) {
        NSLog(@"fetchCounts result: count=%@ error=%@", count, error);
        dispatch_semaphore_signal(sema);
    }];

    long timeout = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    if (timeout != 0) {
        NSLog(@"timed out waiting for feedbackd");
    }
    [connection invalidate];
}

static id call0(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return @"<missing>";
    }
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || strcmp(signature.methodReturnType, @encode(id)) != 0) {
        return @"<non-object>";
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    @try {
        [invocation invoke];
        __unsafe_unretained id value = nil;
        [invocation getReturnValue:&value];
        return value ?: @"<nil>";
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"<exception %@: %@>", exception.name, exception.reason];
    }
}

static BOOL call_bool(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return NO;
    }
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || strcmp(signature.methodReturnType, @encode(BOOL)) != 0) {
        return NO;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    [invocation invoke];
    BOOL value = NO;
    [invocation getReturnValue:&value];
    return value;
}

static void inspect_launch_action(NSString *urlString) {
    dlopen("/System/Library/PrivateFrameworks/FeedbackCore.framework/FeedbackCore", RTLD_NOW);
    Class cls = objc_getClass("FBKLaunchAction");
    if (!cls) {
        NSLog(@"FBKLaunchAction missing");
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    id action = nil;
    SEL initWithURL = NSSelectorFromString(@"initWithURL:");
    SEL initWithWebURL = NSSelectorFromString(@"initWithFeedbackAssistantWebURL:");
    if ([url.host isEqualToString:@"feedbackassistant.apple.com"] &&
        [cls instancesRespondToSelector:initWithWebURL]) {
        action = [[cls alloc] performSelector:initWithWebURL withObject:url];
    } else if ([cls instancesRespondToSelector:initWithURL]) {
        action = [[cls alloc] performSelector:initWithURL withObject:url];
    }
    if (!action) {
        NSLog(@"could not create FBKLaunchAction");
        return;
    }

    NSArray<NSString *> *objectSelectors = @[
        @"description",
        @"url",
        @"action",
        @"itemID",
        @"bundleID",
        @"formIdentifier",
        @"bugFormID",
        @"bugformIDFromURL",
        @"ffuID",
        @"loginToken",
        @"attachments",
        @"extensions",
        @"queryItemsFromURL",
        @"questionAnswerPairs",
        @"questionAnswerPairsFromURL",
        @"questionAnswersPairsFromURLV2",
        @"customBehavior",
        @"configurationToken",
        @"teamType",
        @"itemTypeToShow"
    ];
    NSArray<NSString *> *boolSelectors = @[
        @"launchesFeedback",
        @"launchesInbox",
        @"launchesSurvey",
        @"launchesBatchUI",
        @"showsItem",
        @"isFFUAction",
        @"isShowContentItemAction",
        @"isCaptive",
        @"comesFromFeedbackd",
        @"hasAttachments",
        @"hasFormItemTatToFetch",
        @"shouldMakeFBAVisible",
        @"shouldNotifyOnUpload"
    ];

    printf("URL: %s\n", urlString.UTF8String);
    for (NSString *selector in objectSelectors) {
        id value = call0(action, selector);
        printf("%-34s %s\n", selector.UTF8String, [[value description] UTF8String]);
    }
    for (NSString *selector in boolSelectors) {
        printf("%-34s %s\n", selector.UTF8String, call_bool(action, selector) ? "true" : "false");
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"inspect";
        if ([mode isEqualToString:@"inspect"]) {
            inspect_runtime();
            return 0;
        }
        if ([mode isEqualToString:@"fetch-counts"]) {
            NSString *form = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"seedx:xcode";
            probe_fetch_counts(form);
            return 0;
        }
        if ([mode isEqualToString:@"launch-action"]) {
            NSString *url = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"applefeedback:///new";
            inspect_launch_action(url);
            return 0;
        }
        fprintf(stderr, "usage: %s [inspect|fetch-counts <formIdentifier>|launch-action <url>]\n", argv[0]);
        return 2;
    }
}
