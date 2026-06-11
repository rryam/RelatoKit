on run argv
  set feedbackTitle to item 1 of argv
  set feedbackDescription to item 2 of argv
  set feedbackTopic to item 3 of argv
  set feedbackArea to item 4 of argv
  set feedbackKind to item 5 of argv
  set snapshotPath to item 6 of argv
  set bundleID to item 7 of argv
  set shouldSelectPopups to item 8 of argv
  set shouldSubmit to item 9 of argv

  tell application "Feedback Assistant" to activate
  delay 0.5

  tell application "System Events"
    tell process "Feedback Assistant"
      set frontmost to true
      set targetWindow to window 1
      set targetScroll to scroll area 1 of targetWindow

      if name of targetWindow is "Choose Topic" then
        my chooseTopic(targetScroll, feedbackTopic)
        click button "Continue" of targetWindow
        my waitForTextField("Please provide a descriptive title for your feedback:")
        set targetWindow to window 1
        set targetScroll to scroll area 1 of targetWindow
      end if

      my setTextField(targetScroll, "Please provide a descriptive title for your feedback:", feedbackTitle)
      my setTextArea(targetScroll, "Please describe the issue and what steps we can take to reproduce it", feedbackDescription)

      if bundleID is not "" then
        try
          my setTextField(targetScroll, "Please provide the bundleId or appAppleId of your app:", bundleID)
        end try
      end if

      if shouldSelectPopups is "true" then
        my choosePopup(targetScroll, "Which area are you seeing an issue with?", feedbackArea)

        try
          my choosePopup(targetScroll, "What type of feedback are you reporting?", feedbackKind)
        on error
          my choosePopupAtIndex(targetScroll, 2, feedbackKind)
        end try
      end if

      if bundleID is not "" then
        try
          my setTextField(targetScroll, "Please provide the bundleId or appAppleId of your app:", bundleID)
        end try
      end if

      if snapshotPath is not "" then
        my attachFile(targetScroll, snapshotPath)
      end if

      if shouldSubmit is "true" then
        my clickSubmit(targetWindow, targetScroll)
      end if
    end tell
  end tell
end run

on chooseTopic(targetScroll, wantedTopic)
  tell application "System Events"
    repeat with candidateRow in rows of table 1 of targetScroll
      try
        repeat with candidateElement in UI elements of candidateRow
          try
            if name of candidateElement is wantedTopic then
              set selected of candidateRow to true
              click candidateRow
              delay 0.2
              return
            end if
          end try
        end repeat
      end try
    end repeat
  end tell
  error "Could not find topic: " & wantedTopic
end chooseTopic

on waitForTextField(fieldDescription)
  tell application "System Events"
    repeat 60 times
      try
        tell process "Feedback Assistant"
          set targetScroll to scroll area 1 of window 1
          repeat with candidate in text fields of targetScroll
            try
              if description of candidate is fieldDescription then
                return
              end if
            end try
          end repeat
        end tell
      end try
      delay 0.5
    end repeat
  end tell
  error "Timed out waiting for text field: " & fieldDescription
end waitForTextField

on setTextField(targetScroll, fieldDescription, fieldValue)
  tell application "System Events"
    repeat with candidate in text fields of targetScroll
      try
        if my fieldDescriptionMatches(description of candidate, fieldDescription) then
          set value of candidate to fieldValue
          return
        end if
      end try
    end repeat
  end tell
  error "Could not find text field: " & fieldDescription
end setTextField

on setTextArea(targetScroll, fieldDescription, fieldValue)
  tell application "System Events"
    repeat with candidateScroll in scroll areas of targetScroll
      try
        repeat with candidate in text areas of candidateScroll
          try
            if my fieldDescriptionMatches(description of candidate, fieldDescription) then
              set value of candidate to fieldValue
              return
            end if
          end try
        end repeat
      end try
    end repeat
  end tell
  error "Could not find text area: " & fieldDescription
end setTextArea

on fieldDescriptionMatches(candidateDescription, wantedDescription)
  if candidateDescription is wantedDescription then return true
  if candidateDescription starts with wantedDescription then return true
  return false
end fieldDescriptionMatches

on choosePopup(targetScroll, popupDescription, wantedValue)
  tell application "System Events"
    repeat with candidate in pop up buttons of targetScroll
      try
        if my fieldDescriptionMatches(description of candidate, popupDescription) then
          click candidate
          delay 0.4
          keystroke wantedValue
          delay 0.4
          key code 36
          delay 0.2
          key code 36
          delay 0.4
          if value of candidate is not wantedValue then
            error "Could not select popup value '" & wantedValue & "'; selected '" & (value of candidate) & "'"
          end if
          return
        end if
      end try
    end repeat
  end tell
  error "Could not find popup: " & popupDescription
end choosePopup

on choosePopupAtIndex(targetScroll, popupIndex, wantedValue)
  tell application "System Events"
    set targetPopup to item popupIndex of pop up buttons of targetScroll
    click targetPopup
    delay 0.4
    keystroke wantedValue
    delay 0.4
    key code 36
    delay 0.2
    key code 36
    delay 0.4
    if value of targetPopup is not wantedValue then
      error "Could not select popup value '" & wantedValue & "'; selected '" & (value of targetPopup) & "'"
    end if
  end tell
end choosePopupAtIndex

on attachFile(targetScroll, snapshotPath)
  tell application "System Events"
    click button "Add Attachment   " of targetScroll
    delay 0.3
    key code 125
    key code 125
    key code 36
    delay 0.8
    keystroke "g" using {command down, shift down}
    delay 0.3
    keystroke snapshotPath
    delay 0.2
    key code 36
    delay 0.8
    key code 36
    delay 1.0
  end tell
end attachFile

on clickSubmit(targetWindow, targetScroll)
  tell application "System Events"
    try
      click button "Submit" of targetScroll
      return
    end try

    try
      click button "Submit" of targetWindow
      return
    end try
  end tell
  error "Could not find Submit button. Make sure all required fields and diagnostics are complete."
end clickSubmit
