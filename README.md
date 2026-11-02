# Earphone Silencer

A small macOS app that blocks malfunctioning wired earphone buttons while keeping the audio interface connected.

Requires an Apple silicon Mac running macOS 13 or later, with the Xcode command-line tools installed.

## Build

```sh
zsh build.sh
open 'build/Earphone Silencer.app'
```

Pass an output app path to `build.sh` to choose a different destination. The app is signed locally; it is not notarized for distribution.

## Use

1. Connect your earphones and select them in the device menu.
2. Click **Block Buttons**.
3. Test play/pause and volume while listening to audio.
4. Click **Unblock Buttons** or close the app to restore the controls.

If macOS refuses access, enable Earphone Silencer in **System Settings → Privacy & Security → Input Monitoring**, then quit and reopen the app. Permission is requested only if opening the control interface fails.

After disconnecting and reconnecting the earphones, click **Block Buttons** again. The app does not launch at login or block automatically.

## How it works

The app opens the selected headset's separate consumer-control HID interfaces exclusively through IOKit. It groups USB control interfaces by the parent USB device's registry ID and releases all opened interfaces if one cannot be opened. It does not open audio or microphone interfaces.

Keyboard, pointer, Bluetooth, and mixed keyboard/media interfaces are excluded. Only wired interfaces whose input elements are all consumer controls are offered. Select only your earphones; unrelated USB media controllers may also appear.

Some earphones implement volume or mute within their own hardware, which the app cannot override. Devices without a separate eligible control interface will not appear.

## Checks

The build runs device eligibility checks. To rerun them or list eligible devices:

```sh
'build/Earphone Silencer.app/Contents/MacOS/EarphoneSilencer' --self-test
'build/Earphone Silencer.app/Contents/MacOS/EarphoneSilencer' --list-devices
```

Neither diagnostic flag opens the control interfaces or requests permissions. Physical button suppression and audio playback must be checked with the connected earphones.

Apple API documentation:

- https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen
- https://developer.apple.com/documentation/iokit/1556660-anonymous/kiohidoptionstypeseizedevice
