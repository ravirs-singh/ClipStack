# Keeping your identity out of the launch

What ships under the `halvent` handle, and what would otherwise leak.

## Already scrubbed in this repo
- Git history: the launch branch is a single fresh commit authored by `halvent <halvent@users.noreply.github.com>`. The old history (one commit carried a personal email) is not pushed.
- LICENSE: copyright holder is `halvent`.
- Bundle ID: `com.halvent.clipstack` (Info.plist, Homebrew cask). Changing it resets ClipStack's saved preferences and permission grants on your Mac once; that is expected.
- Video, gallery and README screenshots: the weather card now says Cupertino, not your city. No real clipboard data, screenshots or file names appear anywhere; everything shown is staged.

## Do before pushing from your Mac
1. GitHub → Settings → Emails: tick **Keep my email addresses private** and **Block command line pushes that expose my email**.
2. On your Mac, inside the repo, set a neutral author so future commits don't carry your name or email:
   ```bash
   git config user.name halvent
   git config user.email halvent@users.noreply.github.com
   ```
3. Profile for `halvent`: no real name, no photo of you, no location, no personal links, no company field.
4. Make your old personal ClipStack repo private or delete it once the new one is up. Its history carries your name, and forks or search engines can surface it.

## Code signing exposes your legal name
A Developer ID certificate embeds the account holder's name. Anyone can run `codesign -dvv ClipStack.app` and read `Developer ID Application: <Your Name> (TEAMID)`. Options:
- **Ship unsigned for the launch.** Users right-click → Open once (or `xattr -d com.apple.quarantine`). The README and `install.sh` already handle this; note it in the Product Hunt comment. Most indie open-source Mac apps launch this way.
- **Sign under a company.** Enroll an Apple Developer account as an organization (needs a registered business and D-U-N-S number). The certificate then carries the company name.
- Do not sign with a personal Developer ID if the name matters to you.

## Product Hunt
- Create the maker account as `halvent` with a logo avatar. PH asks for a name; a handle is accepted. Skip Twitter/X and LinkedIn links.
- Hunt it yourself from that account. Don't ask a friend whose profile links back to you.
- The maker comment in `product-hunt.md` is written in first person without any personal details. Keep replies the same way.
- Website field: use the GitHub repo URL, not a personal domain.

## In the app itself
- ClipStack makes no network requests except Open-Meteo for weather (opt-in) and the local Claude Code hook server on 127.0.0.1. No analytics, no crash reporting, no update check, so nothing about users reaches you and nothing about you reaches them.
- The crash log stays at `~/Library/Application Support/ClipStack/ClipStack.log` on the user's machine.

## Things that cannot be hidden
- Apple notarization tickets, if you ever notarize, are tied to your developer account on Apple's side but are not public.
- The git commit trailers link to a Claude Code session URL that only your Anthropic account can open.
