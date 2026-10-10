# Privacy Policy — WithYou

Effective date: 2026-10-09

WithYou is designed to be privacy-friendly. Your thoughts, tasks, reminders and focus sessions stay on your device. There are no accounts to create, and WithYou doesn't register your device with any server.

## What stays on your device
All content you create (captured thoughts, Inbox items, reminders, focus sessions, brain-dump notes, profiles and preferences) is stored only on your device, using Apple's SwiftData framework.

Reminders, focus endings and the optional daily check-in are local notifications, created and scheduled on your device. WithYou doesn't use push notifications and doesn't send a device token anywhere.

## Voice capture
When you use the mic, Apple's speech recognition turns what you say into text. WithYou asks for on-device recognition whenever your iPhone supports it for your language, so your voice stays on your device. Where it doesn't, Apple may process the audio to recognize it, as with keyboard dictation, under Apple's privacy policy. WithYou never receives or stores audio. The microphone is only on while you're capturing.

Capturing with Siri works through Siri, under Apple's privacy policy. WithYou then sorts the words like any other capture (on your device, or with cloud AI if you turned it on).

## AI help
WithYou's AI features (sorting out a capture, breaking a task down, help when you're stuck, picking one thing to do, tidying brain-dump thoughts) only suggest. Nothing changes until you choose it. The one exception is "Capture in WithYou" with Siri, which saves what you asked it to save, sorted the same way, and tells you what it saved. They work in one of three ways:

- **On your device.** On devices that support Apple Intelligence (iOS 26 or later), WithYou uses Apple's on-device language model. This happens entirely on your device.
- **Built-in rules.** Without Apple Intelligence, simple rules on your device give the suggestion.
- **Cloud AI (optional, off by default).** Only if you turn on "Use cloud AI" in Settings, and only when Apple Intelligence isn't available or can't answer that request, a request is sent to WithYou's server, which passes it to Claude (an AI model by Anthropic) and returns the suggestion.

### What a cloud AI request contains
- the text of that one request: for example, the thought you asked to sort out, the task you asked to break down, the titles of the Inbox items and today's reminders when you ask for help picking, or the brain-dump thoughts being tidied
- the small details that request needs, such as your current time and time zone, your morning and evening hours, the energy level you chose and time estimates
- a random anonymous ID that WithYou's server assigns the first time you use cloud AI, so daily limits can be applied. It isn't linked to your name, email, phone number or Apple ID.

### What is kept
WithYou's server doesn't store your words or the AI's replies. It keeps only a count of requests per anonymous ID per day, to apply fair daily limits, and deletes those counts after 35 days. Like any internet connection, the server receives your IP address as part of the request.

The server runs on Supabase (hosting). Anthropic processes each request to produce the reply, under its terms for business customers.

### Turning it off and deleting it
Turning cloud AI off stops sending requests. "Delete my cloud AI data" in Settings deletes the anonymous ID and its usage counts from the server and turns cloud AI off. If you delete the app without doing that, the usage counts are still deleted after 35 days, and the anonymous ID on its own says nothing about you.

## Earlier versions
Earlier versions of WithYou could send a push token, time zone and a random install ID to a WithYou server for notifications. That server has been retired and its records deleted. When you update, WithYou removes the old install ID and its stored secret from your device.

## Third parties
WithYou does not use analytics, advertising SDKs or trackers. WithYou does not sell your data. The only outside services WithYou uses are Supabase and Anthropic, and only for cloud AI, if you turn it on.

## Contact
For support or privacy questions, visit: https://wearewithyou.app/support/
