# Task 6 Testing Guide

## Pre-Testing Setup

### Reset Onboarding Flag
```bash
defaults delete com.lgtvmenubar hasCompletedOnboarding
```

### Clear TV Configuration
```bash
# Clear keychain entries if needed
security delete-generic-password -s "com.lgtvmenubar.tv.config"
```

## Test Cases

### 1. First Launch (Onboarding)

**Expected Behavior:**
- [ ] App launches without dock icon
- [ ] TV icon appears in menu bar
- [ ] Onboarding window appears automatically (500x600)

**Onboarding Step 1 (Welcome):**
- [ ] App icon and welcome message displayed
- [ ] Feature list visible
- [ ] Progress dots show step 1 active
- [ ] "Get Started" button enabled
- [ ] "Skip Setup" button visible

**Onboarding Step 2 (Configuration):**
- [ ] Form fields for TV Name, IP, MAC, Preferred Input
- [ ] Picker shows all HDMI inputs
- [ ] "Back" button works
- [ ] "Connect to TV" button disabled when fields empty
- [ ] "Connect to TV" button enabled when all fields filled

**Onboarding Step 3 (Instructions):**
- [ ] Instructions for TV pairing displayed
- [ ] Progress spinner appears
- [ ] Connection state updates in real-time
- [ ] On connection failure: error shown, returns to step 2
- [ ] On connection success: green checkmark appears
- [ ] "Continue" button enabled after successful connection

**Onboarding Step 4 (Success):**
- [ ] Success message with checkmark
- [ ] Feature summary displayed
- [ ] "Get Started" button closes window
- [ ] `hasCompletedOnboarding` flag set

### 2. Subsequent Launches (No Onboarding)

**Expected Behavior:**
- [ ] App launches without onboarding window
- [ ] Only menu bar icon visible
- [ ] Clicking icon shows popover

### 3. Popover Behavior

**Opening Popover:**
- [ ] Click TV icon → popover appears
- [ ] Popover positioned below menu bar icon
- [ ] Popover has proper focus (cursor blinks in text fields)

**Interactions (KEY TESTS - Must NOT Dismiss):**
- [ ] Click "Power Off" button → command sent, popover stays open
- [ ] Click "Wake TV" button → command sent, popover stays open
- [ ] Click "Connect" button → connection starts, popover stays open
- [ ] Click input picker → menu opens, popover stays open
- [ ] Select input from picker → input changes, popover stays open
- [ ] Click mute button → mute toggles, popover stays open
- [ ] Drag volume slider → volume changes, popover stays open
- [ ] Click volume up/down → volume changes, popover stays open
- [ ] Click gear icon → settings expand, popover stays open
- [ ] Toggle any setting → setting changes, popover stays open
- [ ] Click in form fields → cursor appears, popover stays open
- [ ] Type in form fields → text appears, popover stays open

**Dismissing Popover:**
- [ ] Press Escape key → popover dismisses
- [ ] Click outside popover → popover dismisses
- [ ] Click TV icon again → popover dismisses
- [ ] Click "Quit" button → app terminates

### 4. Settings (Expanded State)

**Expected Behavior:**
- [ ] Click gear icon → settings expand inline
- [ ] Popover width increases from 280 to 350
- [ ] Animation smooth (0.2s easeInOut)
- [ ] All tabs accessible (TV, Automation, General)
- [ ] Click gear icon again → settings collapse
- [ ] Popover width returns to 280

**TV Configuration Tab:**
- [ ] Form fields editable without dismiss
- [ ] "Test Connection" button works
- [ ] "Save" button works
- [ ] "Clear" button works
- [ ] Connection status updates in real-time

**Automation Tab:**
- [ ] All toggles work without dismiss
- [ ] "Save Changes" button works
- [ ] Settings persist after save

**General Tab:**
- [ ] "Launch at login" toggle works
- [ ] "Use keyboard volume keys" toggle works
- [ ] "Grant Access" button opens System Settings
- [ ] Status indicators update correctly

### 5. Keyboard Navigation

**Expected Behavior:**
- [ ] Tab key moves between controls
- [ ] Space bar activates buttons
- [ ] Arrow keys work in pickers
- [ ] Escape key dismisses popover (without saving)
- [ ] Cmd+Q quits app

### 6. Edge Cases

**Multiple Clicks:**
- [ ] Rapidly click TV icon → popover toggles correctly
- [ ] No crashes or visual glitches

**Window Focus:**
- [ ] Switch to other apps → popover stays visible
- [ ] Click back to popover → focus returns correctly
- [ ] No interference with other app's menu bars

**Onboarding Skip:**
- [ ] Click "Skip Setup" at any step → window closes
- [ ] `hasCompletedOnboarding` flag set
- [ ] Menu bar functions normally (no configuration)

**Onboarding Back Navigation:**
- [ ] Step 2 → Back → Step 1 works
- [ ] Step 3 → Back → Step 2 works (connection cancelled)
- [ ] Form data preserved when going back

**Connection Errors:**
- [ ] Invalid IP → error shown, stays on config step
- [ ] Network unreachable → error shown, stays on config step
- [ ] TV rejects pairing → error shown, stays on config step

### 7. Memory & Performance

**Expected Behavior:**
- [ ] No memory leaks (check Activity Monitor)
- [ ] Event monitors cleaned up on quit
- [ ] Popover animations smooth (60fps)
- [ ] No CPU spikes when idle

### 8. Accessibility

**Expected Behavior:**
- [ ] VoiceOver can navigate all controls
- [ ] Tab order logical
- [ ] Focus indicators visible
- [ ] Button labels clear

## Debug Commands

### Check Onboarding Flag
```bash
defaults read com.lgtvmenubar hasCompletedOnboarding
```

### View All App Defaults
```bash
defaults read com.lgtvmenubar
```

### Monitor Logs
```bash
log stream --predicate 'subsystem == "com.lgtvmenubar"' --level debug
```

### Force Reset Everything
```bash
# Delete UserDefaults
defaults delete com.lgtvmenubar

# Delete Keychain
security delete-generic-password -s "com.lgtvmenubar.tv.config"

# Relaunch app
killall LGTVMenuBar
open /path/to/LGTVMenuBar.app
```

## Success Criteria

✅ **All interactions work without dismissing popover**  
✅ **Onboarding completes successfully**  
✅ **Settings persist correctly**  
✅ **Escape and click-outside dismiss work**  
✅ **No memory leaks**  
✅ **No crashes**

## Known Limitations

- Onboarding window cannot be resized (fixed 500x600)
- Onboarding cannot be accessed again after completion (must reset flag)
- Popover width changes are hard-coded (280/350)

## Regression Testing

After confirming Task 6 works, verify existing features still work:
- [ ] Wake-on-LAN
- [ ] Power off
- [ ] Volume control
- [ ] Input switching
- [ ] Launch at login
- [ ] Media key capture
- [ ] Sleep/wake automation
