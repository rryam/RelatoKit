#import "RelatoNativeAutomation.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>

static NSString *RFAString(const char *value) {
    if (value == NULL) { return @""; }
    return [NSString stringWithUTF8String:value] ?: @"";
}

static int RFAFail(char **errorOut, NSString *message) {
    if (errorOut != NULL) {
        *errorOut = strdup(message.UTF8String);
    }
    return 1;
}

typedef void (*RFASLEventPostToPidFunction)(pid_t pid, CGEventRef event);

static void RFAStampEventForPid(CGEventRef event, pid_t pid) {
    if (event == NULL || pid <= 0) { return; }
    CGEventSetIntegerValueField(event, kCGEventTargetUnixProcessID, pid);
}

static RFASLEventPostToPidFunction RFASkyLightPostToPid(void) {
    static RFASLEventPostToPidFunction postToPid = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (handle == NULL) { return; }
        postToPid = (RFASLEventPostToPidFunction)dlsym(handle, "SLEventPostToPid");
    });
    return postToPid;
}

static BOOL RFAPostEventToPid(CGEventRef event, pid_t pid) {
    RFAStampEventForPid(event, pid);
    RFASLEventPostToPidFunction skyLightPostToPid = RFASkyLightPostToPid();
    if (skyLightPostToPid != NULL) {
        skyLightPostToPid(pid, event);
        return YES;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGEventPostToPid(pid, event);
#pragma clang diagnostic pop
    return YES;
}

void RelatoFeedbackAssistantFree(char *value) {
    free(value);
}

static NSString *RFAAttributeString(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) {
        return @"";
    }
    NSString *result;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    } else {
        result = [NSString stringWithFormat:@"%@", value];
    }
    CFRelease(value);
    return result ?: @"";
}

static CFArrayRef RFACopyElementArray(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) {
        return NULL;
    }
    if (CFGetTypeID(value) != CFArrayGetTypeID()) {
        CFRelease(value);
        return NULL;
    }
    return (CFArrayRef)value;
}

static BOOL RFAMatchesString(NSString *candidate, NSString *wanted) {
    if (candidate.length == 0 || wanted.length == 0) { return NO; }
    return [candidate isEqualToString:wanted]
        || [candidate hasPrefix:wanted]
        || [candidate rangeOfString:wanted options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL RFAMatches(AXUIElementRef element, NSString *wanted) {
    return RFAMatchesString(RFAAttributeString(element, kAXTitleAttribute), wanted)
        || RFAMatchesString(RFAAttributeString(element, kAXDescriptionAttribute), wanted)
        || RFAMatchesString(RFAAttributeString(element, kAXValueAttribute), wanted)
        || RFAMatchesString(RFAAttributeString(element, kAXIdentifierAttribute), wanted);
}

static NSString *RFARole(AXUIElementRef element) {
    return RFAAttributeString(element, kAXRoleAttribute);
}

static BOOL RFAIsTextInput(AXUIElementRef element) {
    NSString *role = RFARole(element);
    return [role isEqualToString:NSAccessibilityTextFieldRole] || [role isEqualToString:NSAccessibilityTextAreaRole];
}

static AXUIElementRef RFAFindDescendantWithDepth(AXUIElementRef root, NSInteger depth, BOOL (^predicate)(AXUIElementRef element)) {
    if (root == NULL || depth < 0) { return NULL; }

    CFStringRef attributes[] = { kAXChildrenAttribute, kAXRowsAttribute, kAXVisibleChildrenAttribute, CFSTR("AXSheets") };
    for (NSUInteger attributeIndex = 0; attributeIndex < 4; attributeIndex++) {
        CFArrayRef children = RFACopyElementArray(root, attributes[attributeIndex]);
        if (children == NULL) { continue; }
        CFIndex count = CFArrayGetCount(children);
        for (CFIndex index = 0; index < count; index++) {
            AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, index);
            if (child != NULL && predicate(child)) {
                CFRetain(child);
                CFRelease(children);
                return child;
            }
            AXUIElementRef found = RFAFindDescendantWithDepth(child, depth - 1, predicate);
            if (found != NULL) {
                CFRelease(children);
                return found;
            }
        }
        CFRelease(children);
    }
    return NULL;
}

static AXUIElementRef RFAFindDescendant(AXUIElementRef root, BOOL (^predicate)(AXUIElementRef element)) {
    return RFAFindDescendantWithDepth(root, 12, predicate);
}

static AXUIElementRef RFAFirstWindow(AXUIElementRef app) {
    CFArrayRef windows = RFACopyElementArray(app, kAXWindowsAttribute);
    if (windows == NULL || CFArrayGetCount(windows) == 0) {
        if (windows != NULL) { CFRelease(windows); }
        return NULL;
    }
    AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, 0);
    if (window != NULL) { CFRetain(window); }
    CFRelease(windows);
    return window;
}

static AXUIElementRef RFACopyAncestorWindow(AXUIElementRef element) {
    if (element == NULL) { return NULL; }
    AXUIElementRef current = element;
    CFRetain(current);
    for (NSInteger depth = 0; depth < 16 && current != NULL; depth++) {
        if ([RFARole(current) isEqualToString:NSAccessibilityWindowRole]) {
            return current;
        }

        CFTypeRef parent = NULL;
        AXError error = AXUIElementCopyAttributeValue(current, kAXParentAttribute, &parent);
        CFRelease(current);
        if (error != kAXErrorSuccess || parent == NULL) {
            return NULL;
        }
        current = (AXUIElementRef)parent;
    }
    if (current != NULL) { CFRelease(current); }
    return NULL;
}

static AXUIElementRef RFAFindWindow(AXUIElementRef app, BOOL (^predicate)(AXUIElementRef window)) {
    CFArrayRef windows = RFACopyElementArray(app, kAXWindowsAttribute);
    if (windows == NULL) { return NULL; }
    AXUIElementRef result = NULL;
    CFIndex count = CFArrayGetCount(windows);
    for (CFIndex index = 0; index < count; index++) {
        AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, index);
        if (window != NULL && predicate(window)) {
            result = window;
            CFRetain(result);
            break;
        }
    }
    CFRelease(windows);
    return result;
}

static BOOL RFAPointAndSize(AXUIElementRef element, CGPoint *point, CGSize *size);
static BOOL RFAPress(AXUIElementRef element);

static AXUIElementRef RFAFindButton(AXUIElementRef root, NSString *name) {
    return RFAFindDescendant(root, ^BOOL(AXUIElementRef element) {
        return [RFARole(element) isEqualToString:NSAccessibilityButtonRole] && RFAMatches(element, name);
    });
}

static BOOL RFAPointAndSize(AXUIElementRef element, CGPoint *point, CGSize *size) {
    CFTypeRef positionValue = NULL;
    CFTypeRef sizeValue = NULL;
    BOOL ok = NO;
    if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &positionValue) == kAXErrorSuccess &&
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &sizeValue) == kAXErrorSuccess &&
        positionValue != NULL && sizeValue != NULL &&
        CFGetTypeID(positionValue) == AXValueGetTypeID() &&
        CFGetTypeID(sizeValue) == AXValueGetTypeID() &&
        AXValueGetType(positionValue) == kAXValueCGPointType &&
        AXValueGetType(sizeValue) == kAXValueCGSizeType) {
        AXValueGetValue(positionValue, kAXValueCGPointType, point);
        AXValueGetValue(sizeValue, kAXValueCGSizeType, size);
        ok = YES;
    }
    if (positionValue != NULL) { CFRelease(positionValue); }
    if (sizeValue != NULL) { CFRelease(sizeValue); }
    return ok;
}

static BOOL RFAPress(AXUIElementRef element) {
    return AXUIElementPerformAction(element, kAXPressAction) == kAXErrorSuccess;
}

static BOOL RFAPerformActionOnly(AXUIElementRef element, CFStringRef action) {
    return element != NULL && AXUIElementPerformAction(element, action) == kAXErrorSuccess;
}

static BOOL RFAPressActionOnly(AXUIElementRef element) {
    return RFAPerformActionOnly(element, kAXPressAction);
}

static BOOL RFAPerformActionOnElementOrChild(AXUIElementRef element, CFStringRef action) {
    if (RFAPerformActionOnly(element, action)) { return YES; }
    AXUIElementRef actionElement = RFAFindDescendant(element, ^BOOL(AXUIElementRef child) {
        NSString *role = RFARole(child);
        if (![role isEqualToString:NSAccessibilityButtonRole] &&
            ![role isEqualToString:NSAccessibilityMenuButtonRole] &&
            ![role isEqualToString:NSAccessibilityPopUpButtonRole]) {
            return NO;
        }
        return RFAPerformActionOnly(child, action);
    });
    if (actionElement != NULL) {
        CFRelease(actionElement);
        return YES;
    }
    return NO;
}

static void RFAScrollElementToVisible(AXUIElementRef element) {
    if (element == NULL) { return; }
    AXUIElementPerformAction(element, CFSTR("AXScrollToVisible"));
    [NSThread sleepForTimeInterval:0.25];
}

static BOOL RFAPostCommandKeyToPid(CGKeyCode keyCode, pid_t pid) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    RFAPostEventToPid(down, pid);
    RFAPostEventToPid(up, pid);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

static BOOL RFAPostTextToPid(NSString *text, pid_t pid) {
    for (NSUInteger index = 0; index < text.length; index++) {
        UniChar character = [text characterAtIndex:index];
        CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true);
        CGEventRef up = CGEventCreateKeyboardEvent(NULL, 0, false);
        if (down == NULL || up == NULL) {
            if (down != NULL) { CFRelease(down); }
            if (up != NULL) { CFRelease(up); }
            return NO;
        }
        CGEventKeyboardSetUnicodeString(down, 1, &character);
        CGEventKeyboardSetUnicodeString(up, 1, &character);
        RFAPostEventToPid(down, pid);
        RFAPostEventToPid(up, pid);
        CFRelease(down);
        CFRelease(up);
    }
    return YES;
}

static BOOL RFAPasteTargeted(NSString *value, AXUIElementRef input, AXUIElementRef appElement, NSRunningApplication *app) {
    AXUIElementSetAttributeValue(input, kAXFocusedAttribute, kCFBooleanTrue);
    AXUIElementSetAttributeValue(appElement, kAXFocusedUIElementAttribute, input);
    AXUIElementPerformAction(input, kAXPressAction);
    [NSThread sleepForTimeInterval:0.1];

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSString *previous = [pasteboard stringForType:NSPasteboardTypeString];
    [pasteboard clearContents];
    [pasteboard setString:value forType:NSPasteboardTypeString];

    BOOL ok = RFAPostCommandKeyToPid(0, app.processIdentifier) && RFAPostCommandKeyToPid(9, app.processIdentifier);
    [NSThread sleepForTimeInterval:0.2];

    if (![RFAAttributeString(input, kAXValueAttribute) isEqualToString:value]) {
        AXUIElementSetAttributeValue(input, kAXValueAttribute, (__bridge CFStringRef)@"");
        ok = RFAPostTextToPid(value, app.processIdentifier);
        [NSThread sleepForTimeInterval:0.2];
    }

    [pasteboard clearContents];
    if (previous != nil) {
        [pasteboard setString:previous forType:NSPasteboardTypeString];
    }
    return ok && [RFAAttributeString(input, kAXValueAttribute) isEqualToString:value];
}

static int RFASetText(AXUIElementRef root, NSString *label, NSString *value, AXUIElementRef appElement, NSRunningApplication *runningApp, char **errorOut) {
    AXUIElementRef input = RFAFindDescendant(root, ^BOOL(AXUIElementRef element) {
        return RFAIsTextInput(element) && RFAMatches(element, label);
    });
    if (input == NULL) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not find text input: %@", label]);
    }

    AXUIElementSetAttributeValue(input, kAXFocusedAttribute, kCFBooleanTrue);
    [NSThread sleepForTimeInterval:0.1];
    AXError setError = AXUIElementSetAttributeValue(input, kAXValueAttribute, (__bridge CFStringRef)value);
    if (setError != kAXErrorSuccess) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not set text input %@: %d", label, setError]);
    }

    RFAPasteTargeted(value, input, appElement, runningApp);
    if (![RFAAttributeString(input, kAXValueAttribute) isEqualToString:value]) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Text input did not commit value for %@", label]);
    }
    CFRelease(input);
    return 0;
}

static int RFASelectPopup(AXUIElementRef root, NSArray<NSString *> *labels, NSString *value, NSRunningApplication *runningApp, char **errorOut) {
    AXUIElementRef popup = RFAFindDescendant(root, ^BOOL(AXUIElementRef element) {
        if (![RFARole(element) isEqualToString:NSAccessibilityPopUpButtonRole]) { return NO; }
        for (NSString *label in labels) {
            if (RFAMatches(element, label)) { return YES; }
        }
        return NO;
    });
    if (popup == NULL) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not find popup: %@", [labels componentsJoinedByString:@" / "]]);
    }

    for (NSInteger attempt = 0; attempt < 3; attempt++) {
        AXUIElementSetAttributeValue(popup, kAXValueAttribute, (__bridge CFStringRef)value);
        [NSThread sleepForTimeInterval:0.25];
        if ([RFAAttributeString(popup, kAXValueAttribute) rangeOfString:value options:NSCaseInsensitiveSearch].location != NSNotFound) {
            CFRelease(popup);
            return 0;
        }

        RFAScrollElementToVisible(popup);
        RFAPerformActionOnElementOrChild(popup, CFSTR("AXShowMenu"));
        RFAPerformActionOnElementOrChild(popup, kAXPressAction);
        [NSThread sleepForTimeInterval:0.5];
        AXUIElementRef systemWide = AXUIElementCreateSystemWide();
        AXUIElementRef searchRoots[] = { root, systemWide };
        for (NSUInteger rootIndex = 0; rootIndex < 2; rootIndex++) {
            AXUIElementRef searchRoot = searchRoots[rootIndex];
            AXUIElementRef item = RFAFindDescendant(searchRoot, ^BOOL(AXUIElementRef element) {
                NSString *role = RFARole(element);
                return ([role isEqualToString:NSAccessibilityMenuItemRole] || [role isEqualToString:NSAccessibilityStaticTextRole]) && RFAMatches(element, value);
            });
            BOOL pressed = item != NULL &&
                RFAPressActionOnly(item);
            if (pressed) {
                [NSThread sleepForTimeInterval:0.25];
                if ([RFAAttributeString(popup, kAXValueAttribute) rangeOfString:value options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    CFRelease(item);
                    CFRelease(systemWide);
                    CFRelease(popup);
                    return 0;
                }
            }
            if (item != NULL) { CFRelease(item); }
        }
        CFRelease(systemWide);
    }

    return RFAFail(errorOut, [NSString stringWithFormat:@"Could not select popup value '%@' for %@ in background", value, [labels componentsJoinedByString:@" / "]]);
}

int RelatoFeedbackAssistantFill(
    const char *title,
    const char *description,
    const char *topic,
    const char *area,
    const char *kind,
    const char *snapshot,
    const char *bundleID,
    bool selectPopups,
    bool confirmSubmit,
    char **errorOut
) {
    if (!AXIsProcessTrusted()) {
        return RFAFail(errorOut, @"Accessibility permission is required for native form filling");
    }

    NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.appleseed.FeedbackAssistant"];
    NSRunningApplication *runningApp = apps.firstObject;
    if (runningApp == nil) {
        return RFAFail(errorOut, @"Feedback Assistant is not running");
    }
    AXUIElementRef app = AXUIElementCreateApplication(runningApp.processIdentifier);

    AXUIElementRef chooseTopicWindow = NULL;
    for (NSInteger attempt = 0; attempt < 32 && chooseTopicWindow == NULL; attempt++) {
        chooseTopicWindow = RFAFindWindow(app, ^BOOL(AXUIElementRef window) {
            return RFAMatches(window, @"Choose Topic");
        });
        if (chooseTopicWindow == NULL) { [NSThread sleepForTimeInterval:0.25]; }
    }

    if (chooseTopicWindow != NULL) {
        NSString *topicString = RFAString(topic);
        AXUIElementRef row = RFAFindDescendant(chooseTopicWindow, ^BOOL(AXUIElementRef element) {
            if (![RFARole(element) isEqualToString:NSAccessibilityRowRole]) { return NO; }
            return RFAFindDescendant(element, ^BOOL(AXUIElementRef child) { return RFAMatches(child, topicString); }) != NULL;
        });
        if (row == NULL) {
            CFRelease(app);
            return RFAFail(errorOut, [NSString stringWithFormat:@"Could not find topic: %@", topicString]);
        }
        AXUIElementSetAttributeValue(row, kAXSelectedAttribute, kCFBooleanTrue);
        AXUIElementRef continueButton = RFAFindButton(chooseTopicWindow, @"Continue");
        if (continueButton == NULL || !RFAPress(continueButton)) {
            CFRelease(app);
            return RFAFail(errorOut, @"Could not press Continue");
        }
    }

    AXUIElementRef titleInput = NULL;
    for (NSInteger attempt = 0; attempt < 48 && titleInput == NULL; attempt++) {
        titleInput = RFAFindDescendant(app, ^BOOL(AXUIElementRef element) {
            return RFAIsTextInput(element) && RFAMatches(element, @"Please provide a descriptive title for your feedback:");
        });
        if (titleInput == NULL) { [NSThread sleepForTimeInterval:0.25]; }
    }
    if (titleInput == NULL) {
        CFRelease(app);
        return RFAFail(errorOut, @"Timed out waiting for Feedback Assistant form");
    }

    AXUIElementRef window = RFACopyAncestorWindow(titleInput);
    CFRelease(titleInput);
    if (window == NULL) { window = RFAFirstWindow(app); }
    if (window == NULL) { window = app; CFRetain(window); }
    int result = RFASetText(window, @"Please provide a descriptive title for your feedback:", RFAString(title), app, runningApp, errorOut);
    if (result != 0) { CFRelease(app); return result; }
    result = RFASetText(window, @"Please describe the issue and what steps we can take to reproduce it", RFAString(description), app, runningApp, errorOut);
    if (result != 0) { CFRelease(app); return result; }

    NSString *bundleString = RFAString(bundleID);
    if (bundleString.length > 0) {
        RFASetText(window, @"Please provide the bundleId or appAppleId of your app:", bundleString, app, runningApp, NULL);
    }

    if (selectPopups) {
        result = RFASelectPopup(window, @[@"Which area are you seeing an issue with?"], RFAString(area), runningApp, errorOut);
        if (result != 0) { CFRelease(app); return result; }
        result = RFASelectPopup(window, @[@"What type of feedback are you reporting?", @"What type of issue are you reporting?"], RFAString(kind), runningApp, errorOut);
        if (result != 0) { CFRelease(app); return result; }
    }

    if (confirmSubmit) {
        AXUIElementRef submitButton = RFAFindButton(window, @"Submit");
        if (submitButton == NULL || !RFAPress(submitButton)) {
            CFRelease(app);
            return RFAFail(errorOut, @"Could not find or press Submit button");
        }
    }

    CFRelease(window);
    CFRelease(app);
    return 0;
}
