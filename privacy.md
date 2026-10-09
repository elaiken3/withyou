# Privacy Policy — WithYou

Effective date: 2026-10-08

WithYou is designed to be privacy-friendly. Your thoughts, tasks, reminders and focus sessions stay on your device.

## What stays on your device
All content you create (captured thoughts, Inbox items, reminders, focus sessions, brain-dump notes, profiles and preferences) is stored only on your device, using Apple's SwiftData framework. It is never sent to WithYou or to anyone else.

Reminder and focus notifications are created and scheduled on your device.

## "Make it smaller"
On devices that support Apple Intelligence (iOS 26 or later), "Make it smaller" may use Apple's on-device language model to suggest a smaller first step. This happens entirely on your device. Nothing is sent to WithYou or to any third party. On other devices, the suggestion comes from simple built-in rules.

## What is sent to the WithYou server
Only if **both** of these are true:
- you allowed notifications, and
- the Privacy toggle in Settings ("Share push token with WithYou's server") is on,

the app sends the following to the WithYou backend so it can deliver push notifications:
- install ID (a random identifier generated on your device, not linked to your name, email or Apple ID)
- APNs device token (Apple's push address for this install)
- device timezone
- whether notifications are enabled
- APNs environment (sandbox or production)

When the device first registers, the server issues a random per-install secret. The app stores it in the iOS Keychain and uses it to authorize later changes to this install's record.

No content you create is ever sent. Like any internet connection, the server receives your IP address as part of the request.

## Turning it off
Turning the Privacy toggle off deletes this install's record from the WithYou server and removes the stored secret from your device. If the server can't be reached, the toggle stays on and nothing changes, so you can try again later.

Deleting the app removes everything stored on your device. To also delete the server record, turn the toggle off before deleting the app.

## Third parties
WithYou does not use analytics, advertising SDKs or trackers. WithYou does not sell your data.

## Contact
For support or privacy questions, visit: https://wearewithyou.app/support/
