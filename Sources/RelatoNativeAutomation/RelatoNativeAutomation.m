#import "RelatoNativeAutomation.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>

static NSString *RFAString(const char *value) {
    if (value == NULL) { return @""; }
    return [NSString stringWithUTF8String:value] ?: @"";
}

static BOOL RFADisableForegroundFallback(void) {
    NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];
    if ([environment[@"RELATO_DISABLE_FOREGROUND_FALLBACK"] isEqualToString:@"1"]) {
        return YES;
    }
    return ![environment[@"RELATO_ALLOW_FOREGROUND_FALLBACK"] isEqualToString:@"1"];
}

static int RFAFail(char **errorOut, NSString *message) {
    if (errorOut != NULL) {
        *errorOut = strdup(message.UTF8String);
    }
    return 1;
}

typedef void (*RFASLEventPostToPidFunction)(pid_t pid, CGEventRef event);

static CGWindowID RFAWindowIDContainingPoint(CGPoint point, pid_t pid) {
    CFArrayRef windowInfo = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (windowInfo == NULL) { return 0; }

    CGWindowID result = 0;
    CFIndex count = CFArrayGetCount(windowInfo);
    for (CFIndex index = 0; index < count; index++) {
        NSDictionary *window = (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowInfo, index);
        NSNumber *ownerPID = window[(__bridge NSString *)kCGWindowOwnerPID];
        NSNumber *layer = window[(__bridge NSString *)kCGWindowLayer];
        NSNumber *windowNumber = window[(__bridge NSString *)kCGWindowNumber];
        NSDictionary *boundsDictionary = window[(__bridge NSString *)kCGWindowBounds];
        if (ownerPID == nil || layer == nil || windowNumber == nil || boundsDictionary == nil) {
            continue;
        }
        if (ownerPID.intValue != pid || layer.intValue != 0) {
            continue;
        }

        CGRect bounds = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDictionary, &bounds)) {
            continue;
        }
        if (CGRectContainsPoint(bounds, point)) {
            result = (CGWindowID)windowNumber.unsignedIntValue;
            break;
        }
    }

    CFRelease(windowInfo);
    return result;
}

static void RFAStampEventForPid(CGEventRef event, pid_t pid) {
    if (event == NULL || pid <= 0) { return; }
    CGEventSetIntegerValueField(event, kCGEventTargetUnixProcessID, pid);
}

static void RFAStampMouseEventForPid(CGEventRef event, CGPoint point, pid_t pid) {
    RFAStampEventForPid(event, pid);
    CGWindowID windowID = RFAWindowIDContainingPoint(point, pid);
    if (windowID == 0) { return; }
    CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer, windowID);
    CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, windowID);
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

static AXUIElementRef RFAFindVisibleButton(AXUIElementRef root, NSString *name) {
    __block AXUIElementRef best = NULL;
    __block CGFloat bestY = CGFLOAT_MAX;
    RFAFindDescendant(root, ^BOOL(AXUIElementRef element) {
        if (![RFARole(element) isEqualToString:NSAccessibilityButtonRole] || !RFAMatches(element, name)) {
            return NO;
        }
        CGPoint origin = CGPointZero;
        CGSize size = CGSizeZero;
        if (!RFAPointAndSize(element, &origin, &size) || size.width <= 0 || size.height <= 0) {
            return NO;
        }
        if (origin.y < bestY) {
            if (best != NULL) { CFRelease(best); }
            best = element;
            CFRetain(best);
            bestY = origin.y;
        }
        return NO;
    });
    return best;
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

static CGPoint RFAMouseEventPoint(CGPoint point) {
    return point;
}

static BOOL RFAClickElement(AXUIElementRef element) {
    CGPoint origin = CGPointZero;
    CGSize size = CGSizeZero;
    if (!RFAPointAndSize(element, &origin, &size)) { return NO; }
    CGPoint point = RFAMouseEventPoint(CGPointMake(origin.x + size.width / 2.0, origin.y + size.height / 2.0));
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    [NSThread sleepForTimeInterval:0.2];
    return YES;
}

static BOOL RFAClickElementAtRatio(AXUIElementRef element, CGFloat xRatio, CGFloat yRatio) {
    CGPoint origin = CGPointZero;
    CGSize size = CGSizeZero;
    if (!RFAPointAndSize(element, &origin, &size)) { return NO; }
    CGPoint point = RFAMouseEventPoint(CGPointMake(origin.x + size.width * xRatio, origin.y + size.height * yRatio));
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    [NSThread sleepForTimeInterval:0.2];
    return YES;
}

static BOOL RFAClickPoint(CGPoint point) {
    point = RFAMouseEventPoint(point);
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    [NSThread sleepForTimeInterval:0.25];
    return YES;
}

static BOOL RFAClickElementAtRatioToPid(AXUIElementRef element, CGFloat xRatio, CGFloat yRatio, pid_t pid) {
    CGPoint origin = CGPointZero;
    CGSize size = CGSizeZero;
    if (!RFAPointAndSize(element, &origin, &size)) { return NO; }
    CGPoint point = RFAMouseEventPoint(CGPointMake(origin.x + size.width * xRatio, origin.y + size.height * yRatio));
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventSetIntegerValueField(down, kCGMouseEventClickState, 1);
    CGEventSetIntegerValueField(up, kCGMouseEventClickState, 1);
    RFAStampMouseEventForPid(down, point, pid);
    RFAStampMouseEventForPid(up, point, pid);
    RFAPostEventToPid(down, pid);
    RFAPostEventToPid(up, pid);
    CFRelease(down);
    CFRelease(up);
    [NSThread sleepForTimeInterval:0.25];
    return YES;
}

static BOOL RFAClickElementToPid(AXUIElementRef element, pid_t pid) {
    return RFAClickElementAtRatioToPid(element, 0.5, 0.5, pid);
}

static BOOL RFAPressHitTestedElementAtRatio(AXUIElementRef element, CGFloat xRatio, CGFloat yRatio) {
    CGPoint origin = CGPointZero;
    CGSize size = CGSizeZero;
    if (!RFAPointAndSize(element, &origin, &size)) { return NO; }

    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    AXUIElementRef hitElement = NULL;
    CGPoint point = CGPointMake(origin.x + size.width * xRatio, origin.y + size.height * yRatio);
    AXError error = AXUIElementCopyElementAtPosition(systemWide, point.x, point.y, &hitElement);
    CFRelease(systemWide);
    if (error != kAXErrorSuccess || hitElement == NULL) {
        return NO;
    }

    BOOL pressed = RFAPress(hitElement);
    CFRelease(hitElement);
    return pressed;
}

static BOOL RFAPress(AXUIElementRef element) {
    if (AXUIElementPerformAction(element, kAXPressAction) == kAXErrorSuccess) {
        return YES;
    }
    return RFAClickElement(element);
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

static void RFARaiseWindow(AXUIElementRef window) {
    if (window == NULL) { return; }
    AXUIElementPerformAction(window, kAXRaiseAction);
    AXUIElementSetAttributeValue(window, kAXMainAttribute, kCFBooleanTrue);
    AXUIElementSetAttributeValue(window, kAXFocusedAttribute, kCFBooleanTrue);
}

static void RFAScrollElementToVisible(AXUIElementRef element) {
    if (element == NULL) { return; }
    AXUIElementPerformAction(element, CFSTR("AXScrollToVisible"));
    [NSThread sleepForTimeInterval:0.25];
}

static BOOL RFAPostCommandKey(CGKeyCode keyCode) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

static BOOL RFAPostModifiedKey(CGKeyCode keyCode, CGEventFlags flags) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

static BOOL RFAPostModifiedKeyToPid(CGKeyCode keyCode, CGEventFlags flags, pid_t pid) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    RFAPostEventToPid(down, pid);
    RFAPostEventToPid(up, pid);
    CFRelease(down);
    CFRelease(up);
    return YES;
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

static BOOL RFAPasteForeground(NSString *value, AXUIElementRef input, NSRunningApplication *app) {
    [app activateWithOptions:0];
    [NSThread sleepForTimeInterval:0.3];
    AXUIElementSetAttributeValue(input, kAXFocusedAttribute, kCFBooleanTrue);
    AXUIElementPerformAction(input, kAXPressAction);
    [NSThread sleepForTimeInterval:0.1];

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSString *previous = [pasteboard stringForType:NSPasteboardTypeString];
    [pasteboard clearContents];
    [pasteboard setString:value forType:NSPasteboardTypeString];

    BOOL ok = RFAPostCommandKey(0) && RFAPostCommandKey(9);
    [NSThread sleepForTimeInterval:0.2];

    [pasteboard clearContents];
    if (previous != nil) {
        [pasteboard setString:previous forType:NSPasteboardTypeString];
    }
    return ok;
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
    if (![RFAAttributeString(input, kAXValueAttribute) isEqualToString:value] && !RFADisableForegroundFallback()) {
        RFAPasteForeground(value, input, runningApp);
    }
    if (![RFAAttributeString(input, kAXValueAttribute) isEqualToString:value]) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Text input did not commit value for %@", label]);
    }
    CFRelease(input);
    return 0;
}

static BOOL RFAPostText(NSString *text) {
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
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(down);
        CFRelease(up);
    }
    return YES;
}

static BOOL RFAPostKey(CGKeyCode keyCode) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

static BOOL RFAPostKeyToPid(CGKeyCode keyCode, pid_t pid) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, keyCode, false);
    if (down == NULL || up == NULL) {
        if (down != NULL) { CFRelease(down); }
        if (up != NULL) { CFRelease(up); }
        return NO;
    }
    RFAPostEventToPid(down, pid);
    RFAPostEventToPid(up, pid);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

static BOOL RFASystemEventsKeyCode(CGKeyCode keyCode) {
    NSString *script = [NSString stringWithFormat:@"tell application \"System Events\" to key code %hu", keyCode];
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *error = nil;
    [appleScript executeAndReturnError:&error];
    return error == nil;
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
        if (RFADisableForegroundFallback()) {
            RFAPerformActionOnElementOrChild(popup, CFSTR("AXShowMenu"));
            RFAClickElementToPid(popup, runningApp.processIdentifier);
            RFAPerformActionOnElementOrChild(popup, kAXPressAction);
        } else {
            RFAPress(popup);
        }
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
                (RFAPressActionOnly(item) ||
                 (RFADisableForegroundFallback() && RFAClickElementToPid(item, runningApp.processIdentifier)) ||
                 (!RFADisableForegroundFallback() && RFAPress(item)));
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

    if (RFADisableForegroundFallback()) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not select popup value '%@' for %@ without foreground fallback", value, [labels componentsJoinedByString:@" / "]]);
    }

    [runningApp activateWithOptions:0];
    [NSThread sleepForTimeInterval:0.2];
    RFAPress(popup);
    [NSThread sleepForTimeInterval:0.3];
    RFAPostText(value);
    RFAPostKey(36);
    [NSThread sleepForTimeInterval:0.1];
    RFAPostKey(36);
    [NSThread sleepForTimeInterval:0.2];

    if ([RFAAttributeString(popup, kAXValueAttribute) rangeOfString:value options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return 0;
    }
    return RFAFail(errorOut, [NSString stringWithFormat:@"Could not select popup value '%@' for %@", value, [labels componentsJoinedByString:@" / "]]);
}

static AXUIElementRef RFAFindAttachmentFileMenuItem(void) {
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    NSArray<NSString *> *labels = @[@"Choose File", @"Add File"];
    AXUIElementRef item = NULL;
    for (NSInteger attempt = 0; attempt < 10 && item == NULL; attempt++) {
        item = RFAFindDescendant(systemWide, ^BOOL(AXUIElementRef element) {
            if (![RFARole(element) isEqualToString:NSAccessibilityMenuItemRole]) { return NO; }
            for (NSString *label in labels) {
                if (RFAMatches(element, label)) { return YES; }
            }
            return NO;
        });
        if (item == NULL) { [NSThread sleepForTimeInterval:0.1]; }
    }
    CFRelease(systemWide);
    return item;
}

static BOOL RFASelectAttachmentFileMenuItem(AXUIElementRef root, NSRunningApplication *runningApp, char **errorOut) {
    AXUIElementRef button = RFAFindVisibleButton(root, @"Add Attachment");
    if (button == NULL) {
        button = RFAFindButton(root, @"Add Attachment");
    }
    if (button == NULL) {
        RFAFail(errorOut, @"Could not find Add Attachment button");
        return NO;
    }
    CGPoint buttonOrigin = CGPointZero;
    CGSize buttonSize = CGSizeZero;
    BOOL hasButtonFrame = RFAPointAndSize(button, &buttonOrigin, &buttonSize);

    RFAScrollElementToVisible(button);
    hasButtonFrame = RFAPointAndSize(button, &buttonOrigin, &buttonSize);
    AXUIElementRef item = NULL;

    if (RFAPerformActionOnElementOrChild(button, CFSTR("AXShowMenu"))) {
        [NSThread sleepForTimeInterval:0.6];
        item = RFAFindAttachmentFileMenuItem();
        if (item != NULL) {
            BOOL pressed = RFAPressActionOnly(item);
            CFRelease(item);
            CFRelease(button);
            if (!pressed) {
                RFAFail(errorOut, @"Could not choose Add Attachment > Choose File");
                return NO;
            }
            [NSThread sleepForTimeInterval:0.8];
            return YES;
        }
    }

    if (!RFAClickElementAtRatioToPid(button, 0.9, 0.5, runningApp.processIdentifier)) {
        CFRelease(button);
        RFAFail(errorOut, @"Could not press Add Attachment button");
        return NO;
    }
    [NSThread sleepForTimeInterval:0.6];

    item = RFAFindAttachmentFileMenuItem();
    if (item != NULL) {
        BOOL pressed = RFAPressActionOnly(item);
        CFRelease(item);
        CFRelease(button);
        if (!pressed) {
            RFAFail(errorOut, @"Could not choose Add Attachment > Choose File");
            return NO;
        }
        [NSThread sleepForTimeInterval:0.8];
        return YES;
    }

    if (RFAPerformActionOnElementOrChild(button, kAXPressAction)) {
        [NSThread sleepForTimeInterval:0.6];
        item = RFAFindAttachmentFileMenuItem();
        if (item != NULL) {
            BOOL pressed = RFAPressActionOnly(item);
            CFRelease(item);
            CFRelease(button);
            if (!pressed) {
                RFAFail(errorOut, @"Could not choose Add Attachment > Choose File");
                return NO;
            }
            [NSThread sleepForTimeInterval:0.8];
            return YES;
        }
    }

    if (RFADisableForegroundFallback()) {
        CFRelease(button);
        RFAFail(errorOut, @"Could not open Add Attachment menu without foreground fallback");
        return NO;
    }

    [runningApp activateWithOptions:0];
    [NSThread sleepForTimeInterval:0.25];
    RFARaiseWindow(root);
    [NSThread sleepForTimeInterval:0.2];
    RFAScrollElementToVisible(button);
    hasButtonFrame = RFAPointAndSize(button, &buttonOrigin, &buttonSize);
    if (!RFAClickElementAtRatio(button, 0.9, 0.5) &&
        !RFAClickElementAtRatioToPid(button, 0.9, 0.5, runningApp.processIdentifier) &&
        !RFAPressHitTestedElementAtRatio(button, 0.9, 0.5) &&
        !RFAClickElementAtRatio(button, 0.9, 0.5)) {
        CFRelease(button);
        RFAFail(errorOut, @"Could not press Add Attachment button");
        return NO;
    }
    CFRelease(button);
    [NSThread sleepForTimeInterval:0.6];

    item = RFAFindAttachmentFileMenuItem();
    if (item == NULL) {
        if (!hasButtonFrame) {
            RFAFail(errorOut, @"Could not locate Add Attachment menu geometry");
            return NO;
        }
        CGPoint chooseFilePoint = CGPointMake(buttonOrigin.x + buttonSize.width * 1.25, buttonOrigin.y + buttonSize.height * 2.8);
        RFAClickPoint(chooseFilePoint);
        [NSThread sleepForTimeInterval:0.8];
        return YES;
    }
    BOOL pressed = RFAPressActionOnly(item);
    CFRelease(item);
    if (!pressed) {
        RFAFail(errorOut, @"Could not choose Add Attachment > Choose File");
        return NO;
    }
    [NSThread sleepForTimeInterval:0.8];
    return YES;
}

static BOOL RFAPasteTextForeground(NSString *value) {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSString *previous = [pasteboard stringForType:NSPasteboardTypeString];
    [pasteboard clearContents];
    [pasteboard setString:value forType:NSPasteboardTypeString];

    BOOL ok = RFAPostCommandKey(9);
    [NSThread sleepForTimeInterval:0.2];

    [pasteboard clearContents];
    if (previous != nil) {
        [pasteboard setString:previous forType:NSPasteboardTypeString];
    }
    return ok;
}

static BOOL RFAPasteTextToPid(NSString *value, pid_t pid) {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSString *previous = [pasteboard stringForType:NSPasteboardTypeString];
    [pasteboard clearContents];
    [pasteboard setString:value forType:NSPasteboardTypeString];

    BOOL ok = RFAPostCommandKeyToPid(9, pid);
    [NSThread sleepForTimeInterval:0.2];

    [pasteboard clearContents];
    if (previous != nil) {
        [pasteboard setString:previous forType:NSPasteboardTypeString];
    }
    return ok;
}

static int RFANavigateOpenPanelToPath(AXUIElementRef picker, NSString *path, NSRunningApplication *runningApp, char **errorOut) {
    RFAClickElementToPid(picker, runningApp.processIdentifier);
    [NSThread sleepForTimeInterval:0.1];

    RFAPostModifiedKeyToPid(5, kCGEventFlagMaskCommand | kCGEventFlagMaskShift, runningApp.processIdentifier);
    [NSThread sleepForTimeInterval:0.3];
    RFAPasteTextToPid(path, runningApp.processIdentifier);
    RFAPostKeyToPid(36, runningApp.processIdentifier);
    [NSThread sleepForTimeInterval:0.2];

    AXUIElementRef pathField = RFAFindDescendant(picker, ^BOOL(AXUIElementRef element) {
        return RFAIsTextInput(element) && RFAMatches(element, @"PathTextField");
    });
    if (pathField != NULL) {
        CFRelease(pathField);
        if (RFADisableForegroundFallback()) {
            return RFAFail(errorOut, @"Attachment picker did not commit background Go to Folder input");
        }
        [runningApp activateWithOptions:0];
        [NSThread sleepForTimeInterval:0.2];
        RFAClickElement(picker);
        [NSThread sleepForTimeInterval:0.1];
        if (!RFAPostModifiedKey(5, kCGEventFlagMaskCommand | kCGEventFlagMaskShift)) {
            return RFAFail(errorOut, @"Could not open Go to Folder in attachment picker");
        }
        [NSThread sleepForTimeInterval:0.3];
        if (!RFAPasteTextForeground(path)) {
            return RFAFail(errorOut, @"Could not paste attachment path into Go to Folder");
        }
        RFAPostKey(36);
        [NSThread sleepForTimeInterval:0.2];
        pathField = RFAFindDescendant(picker, ^BOOL(AXUIElementRef element) {
            return RFAIsTextInput(element) && RFAMatches(element, @"PathTextField");
        });
        if (pathField != NULL) {
            CFRelease(pathField);
            RFASystemEventsKeyCode(36);
        }
    }
    [NSThread sleepForTimeInterval:0.6];

    AXUIElementRef openButton = NULL;
    for (NSInteger attempt = 0; attempt < 10 && openButton == NULL; attempt++) {
        openButton = RFAFindButton(picker, @"Attach");
        if (openButton == NULL) { openButton = RFAFindButton(picker, @"Open"); }
        if (openButton == NULL) { openButton = RFAFindButton(picker, @"Choose"); }
        if (openButton == NULL) { [NSThread sleepForTimeInterval:0.1]; }
    }
    if (openButton == NULL || !RFAPress(openButton)) {
        if (openButton != NULL) { CFRelease(openButton); }
        return RFAFail(errorOut, @"Could not find attachment picker Attach button");
    }
    CFRelease(openButton);
    [NSThread sleepForTimeInterval:0.6];
    return 0;
}

static int RFAAttachFile(AXUIElementRef root, NSString *path, AXUIElementRef app, NSRunningApplication *runningApp, char **errorOut) {
    if (!RFASelectAttachmentFileMenuItem(root, runningApp, errorOut)) {
        return 1;
    }

    AXUIElementRef picker = RFAFindWindow(app, ^BOOL(AXUIElementRef window) {
        BOOL hasPickerButton = RFAFindButton(window, @"Attach") != NULL || RFAFindButton(window, @"Open") != NULL || RFAFindButton(window, @"Choose") != NULL;
        return hasPickerButton && (RFAMatches(window, @"Open") || RFAMatches(window, @"Choose") || RFAMatches(window, @"Attach"));
    });
    if (picker == NULL) {
        picker = RFAFindDescendant(app, ^BOOL(AXUIElementRef element) {
            BOOL hasPickerButton = RFAFindButton(element, @"Attach") != NULL || RFAFindButton(element, @"Open") != NULL || RFAFindButton(element, @"Choose") != NULL;
            return hasPickerButton && (RFAMatches(element, @"Open") || RFAMatches(element, @"Choose") || RFAMatches(element, @"Attach") || [RFARole(element) isEqualToString:NSAccessibilitySheetRole]);
        });
    }
    if (picker == NULL) {
        return RFAFail(errorOut, @"Native file attachment picker did not open");
    }

    int result = RFANavigateOpenPanelToPath(picker, path, runningApp, errorOut);
    CFRelease(picker);
    return result;
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

    NSString *snapshotString = RFAString(snapshot);
    if (snapshotString.length > 0) {
        result = RFAAttachFile(window, snapshotString, app, runningApp, errorOut);
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
