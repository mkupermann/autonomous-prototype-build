# User-path verification (long form)

The short version is in `SKILL.md`: structural green is not done; the user-path command must also be green. This document is the tooling matrix and the platform-specific recipes.

## The principle

For every contract, ask: **"What is the actual sequence of actions a real user takes to use this thing, and what would they see if it worked?"**

- Web app: user opens the URL → clicks login → sees their dashboard.
- macOS app: user double-clicks a `.md` file in Finder → window appears on the screen they're on → preview pane shows rendered Markdown.
- Mobile app: user taps the app icon → home screen loads → first item is visible.
- TUI: user runs `myapp` → screen shows the menu → arrow keys navigate.

The user-path verification command must follow that sequence (or as close as automation allows) and assert what the user would assert: "yes, I see X."

## Tooling matrix

| Stack | Recommended tool | What to verify | Example |
|---|---|---|---|
| **Web app** | [Playwright](https://playwright.dev) | DOM contains expected text/elements; visual regression vs baseline screenshot; no console errors | `npx playwright test e2e/spec.ts` |
| **Web app (lighter)** | curl + grep, or Puppeteer/CDP directly | Page returns 200; HTML contains expected fragment; computed styles correct | `curl -s localhost:3000 \| grep -q 'Welcome'` |
| **macOS native** | `osascript` UI scripting; `screencapture` + OCR (`tesseract` or Vision); built-in `--user-path-test` mode | Window exists; window is on the user's screen; expected text appears; `WKWebView`/`WebView` `didFinish` event fired | `osascript -e 'tell application "System Events" to count windows of process "X"' = 1` + `screencapture window.png && tesseract window.png - \| grep "expected"` |
| **macOS native (programmatic)** | Accessibility API (`AXUIElementCopyAttributeValue`); inject a `--user-path-test` mode that fakes user actions and dumps view state to a file | Same UI tree assertions a real user makes; emit a structured "PASS/FAIL" line a shell script can check | `myapp --user-path-test sample.md \| grep "rendered_chars=>0"` |
| **iOS / iPadOS** | XCUITest; `xcodebuild test` | Same | XCUITest assertions in CI |
| **Android** | Espresso; UI Automator | Same | `./gradlew connectedAndroidTest` |
| **CLI / TUI** | `expect` scripts; `tmux capture-pane`; vhs (charm.sh) for terminal recording diff | What the user sees in the terminal at each step | `vhs record demo.tape && diff demo.cast baseline.cast` |
| **Visual / pixel-level** | `screencapture` + `cmp` against baseline; perceptualdiff; resemble.js | Pixels in expected regions match (with tolerance) | `screencapture -R x,y,w,h out.png && perceptualdiff out.png baseline.png` |

## Web app: the Playwright recipe

For any web deliverable, Playwright is the default.

```bash
# Install
npm i -D @playwright/test
npx playwright install chromium
```

```typescript
// tests/e2e/userpath.spec.ts
import { test, expect } from '@playwright/test';
test('user can complete the core flow', async ({ page }) => {
    await page.goto('http://localhost:3000');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.getByLabel('Email').fill('test@example.com');
    await page.getByLabel('Password').fill('testpass');
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('Welcome back')).toBeVisible();
    page.on('console', msg => { if (msg.type() === 'error') throw new Error(msg.text()); });
});
```

```bash
# Contract command — the user-path gate
npx playwright test tests/e2e/userpath.spec.ts
```

This fails if the user can't sign in, OR if a page renders blank, OR if a JS error occurs — the same things the user would observe.

## macOS-native: the workarounds

Claude Code does NOT have screen recording permission by default in this environment. Workarounds:

### 1. Inject a debug hook (`--user-path-test`)

Add a CLI mode that programmatically opens the file the same way the user would (`NSDocumentController.openDocument(withContentsOf:)` or `application(_:open:)`), waits for the WKWebView's `didFinish` navigation event, then dumps the rendered HTML / view tree to stdout. The shell test asserts on that. Same pattern as Selenium's "headless mode" for browsers.

```bash
myapp --user-path-test sample.md > out.json
jq '.rendered_chars > 0' out.json
```

### 2. Write to a file-backed log instead of `os_log`

macOS 14+ redacts non-Apple `NSLog` output as `<private>`. A simple `FileHandle`-backed logger sidesteps that and gives the test scripts ground truth.

### 3. Use `osascript` for sanity

`tell application "System Events" to count windows of process "X"` and similar read-only window queries don't always need full Accessibility permission. Use them as a smoke test.

### 4. Pixel-level: grant Screen Recording once

For pixel-level confidence, grant Claude Code Screen Recording permission once (System Settings → Privacy & Security → Screen Recording). After that, `screencapture -R x,y,w,h out.png` works programmatically.

## Where this gate lives in the loop

The user-path verification runs **after** every successful structural check, **before** writing the success report. If structural is green and user-path is red, the iteration is NOT done — pick a new move. Only when both are green does the agent write `<status_file>.success.md`.

```
gap_structural = compare(snapshot, structural_contract)
gap_userpath   = compare(snapshot, userpath_contract)
if gap_structural.passes() and gap_userpath.passes(): break
# else: pick a move that closes the larger of the two gaps
```

## When you can skip this gate

You CANNOT skip it for any UI deliverable. You CAN skip it for:

- Pure libraries with no UI (the API IS the user surface).
- CLI tools whose entire output is to stdout/stderr (the textual output IS what the user sees).
- Backend services with only programmatic clients (the integration test IS the user test).

If unsure, default to including it.
