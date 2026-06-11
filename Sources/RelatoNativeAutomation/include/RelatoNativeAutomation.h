#ifndef RELATO_NATIVE_AUTOMATION_H
#define RELATO_NATIVE_AUTOMATION_H

#include <stdbool.h>

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
);

void RelatoFeedbackAssistantFree(char *value);

#endif
