# Closed test checklist (Google Play)

**VERIFY IN YOUR PLAY CONSOLE.** The rule below comes from Google's help article "Test your app before publishing / closed testing requirements for new personal developer accounts" (support.google.com/googleplay/android-developer/answer/14151465), read on 2026-11-03. It said, for personal accounts created after 13 November 2023: at least **12 testers** must be opted in to your closed test when you apply for production access, **continuously for the preceding 14 days**; a tester who opts out before 14 days does not count, and opting out and back in needs the 14 days to be consecutive. Google changes these numbers and who they apply to. Does it apply to you? Check the Console dashboard ("Finish setting up / Apply for production") and whether your developer account is a personal one created after that date. Organisation accounts may be exempt: **unverified**.

## Date arithmetic

Let D be the date the 12th tester is opted in (all 12 must stay in). The earliest day you can apply is **D + 14 days**.

| 12th tester opts in (D) | Earliest apply date (D + 14) |
| --- | --- |
| Tue 2026-11-10 | Tue 2026-11-24 |
| Tue 2026-11-17 | Tue 2026-12-01 |
| Tue 2026-11-24 | Tue 2026-12-08 |
| Tue 2026-12-01 | Tue 2026-12-15 |

(Computed with Python's `date`; the day count to treat as day 0 is a Console detail, so add a one-day safety margin.) Plan back from your launch date: launch date minus review time (Google says review of the production application can take days; **verify the current figure**) minus 14 days minus recruiting time. Every dropout that resets the count pushes the date out, so recruit **15 to 20 people** to be safe for 12. Today is 2026-11-03; a realistic best case is: build uploaded this week, testers recruited by Tue 2026-11-17, apply from Tue 2026-12-01.

## Before you can upload a build

- [ ] Play Console developer account created and identity verification done (can take days).
- [ ] App created with name Looprun, free, default language.
- [ ] Play App Signing enabled (default for new apps).
- [ ] First signed AAB built with `.github/workflows/release-android.yml`; version code increases per upload.
- [ ] Privacy policy hosted at a public URL ([PRIVACY_POLICY_URL]) and entered.
- [ ] App content forms complete: Data safety (`data-safety-answers.md`), ads (no), target audience 18+, content rating (`listing.md`), app access, location and foreground service declarations (`foreground-service-declaration.md`), account deletion URL.
- [ ] In-app prominent disclosure implemented (`location-disclosure.md`).
- [ ] Store listing draft saved (`listing.md`), icon, feature graphic, at least 2 screenshots.

## Run the test

- [ ] Testing > Closed testing > create a track (or use the default), add a tester list (email list or Google Group), upload the AAB, roll out.
- [ ] Copy the opt-in link into `tester-guide.md` and send it.
- [ ] Track opt-in count daily; keep a spreadsheet: name, Google email, opted in on, still opted in.
- [ ] Ship at least one update during the 14 days if you have fixes (testers get it automatically); the Console expects the testers to be engaged, so ask them to actually open the app.
- [ ] Collect feedback and write down what you changed (Google's application form asks about the test and how you used feedback; **verify**).
- [ ] On D + 14 check the dashboard shows the requirement met, then apply for production access and answer the questions truthfully.

## After production access is granted

- [ ] Create a production release from the tested build or newer, staged rollout (for example 20 percent) at first.
- [ ] Watch server logs (Crashlytics once added) ([looprun-backend `docs/RUNBOOK.md`](https://github.com/VivekMakwana24/looprun-backend/blob/main/docs/RUNBOOK.md)) and set up the uptime monitor.
- [ ] Keep the privacy policy, Data safety answers and app behaviour in sync with every release.
