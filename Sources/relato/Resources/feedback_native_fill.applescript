on run argv
  set feedbackTitle to item 1 of argv
  set feedbackDescription to item 2 of argv
  set feedbackArea to item 3 of argv
  set feedbackKind to item 4 of argv
  set snapshotPath to item 5 of argv
  set bundleID to item 6 of argv
  set shouldSelectPopups to item 7 of argv

  tell application "Feedback Assistant" to activate
  delay 0.5

  tell application "System Events"
    tell process "Feedback Assistant"
      set frontmost to true
      set targetWindow to window 1
      set targetScroll to scroll area 1 of targetWindow

      my setTextField(targetScroll, "Please provide a descriptive title for your feedback:", feedbackTitle)
      my setTextArea(targetScroll, "Please describe the issue and what steps we can take to reproduce it", feedbackDescription)

      if bundleID is not "" then
        try
          my setTextField(targetScroll, "Please provide the bundleId or appAppleId of your app:", bundleID)
        end try
      end if

      if shouldSelectPopups is "true" then
        try
          my choosePopup(targetScroll, "Which area are you seeing an issue with?", feedbackArea)
        end try

        try
          my choosePopup(targetScroll, "What type of feedback are you reporting?", feedbackKind)
        end try
      end if

      if snapshotPath is not "" then
        my attachFile(targetScroll, snapshotPath)
      end if
    end tell
  end tell
end run

on setTextField(targetScroll, fieldDescription, fieldValue)
  tell application "System Events"
    repeat with candidate in text fields of targetScroll
      try
        if description of candidate is fieldDescription then
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
            if description of candidate is fieldDescription then
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

on choosePopup(targetScroll, popupDescription, wantedValue)
  tell application "System Events"
    repeat with candidate in pop up buttons of targetScroll
      try
        if description of candidate is popupDescription then
          click candidate
          delay 0.4
          keystroke wantedValue
          delay 0.4
          key code 36
          delay 0.2
          key code 36
          delay 0.4
          return
        end if
      end try
    end repeat
  end tell
  error "Could not find popup: " & popupDescription
end choosePopup

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
