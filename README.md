# Sleight

[![CI](https://github.com/derodero24/sleight/actions/workflows/ci.yml/badge.svg)](https://github.com/derodero24/sleight/actions/workflows/ci.yml)

Tap/hold key remapping for macOS, without a driver.

Give a key two jobs: tap it to send one key, hold it to become a modifier.

```
Caps Lock      tap -> Escape     hold -> Control
Right Option   tap -> (nothing)  hold -> Control+Option+Shift+Command
```

Sleight uses `CGEventTap`, which is built into macOS. There is no kernel
extension, no DriverKit system extension, and no virtual HID device to install or
approve.

## Requirements

macOS 13 or later, and Xcode Command Line Tools. There is no download - you build
it, which for an app that asks for Accessibility is arguably the honest way round.

```
git clone https://github.com/derodero24/sleight.git
cd sleight
./Scripts/create-signing-cert.sh   # once, ever
./Scripts/install.sh               # build, install to /Applications, launch
```

Sleight makes no network connections of any kind: there is no networking code in
the source, no analytics, and no entitlements file. It reads keyboard events,
writes `~/.config/sleight/config.json`, and logs to `~/Library/Logs/Sleight.log`.
To remove it: quit from the menu, delete `/Applications/Sleight.app` and those
two paths, and turn its entry off in Accessibility settings.

## Why

Getting tap/hold on macOS normally means Karabiner-Elements, which installs a
DriverKit virtual keyboard driver. That driver has broken several times on macOS 26
([#4314](https://github.com/pqrs-org/Karabiner-Elements/issues/4314),
[#4371](https://github.com/pqrs-org/Karabiner-Elements/issues/4371),
[#4402](https://github.com/pqrs-org/Karabiner-Elements/issues/4402),
[#4409](https://github.com/pqrs-org/Karabiner-Elements/issues/4409)), and it is a
lot of machinery for what most people actually want, which is one or two keys doing
double duty.

The driver-free alternatives each cover one slice of the problem:

| | driver | tap/hold | which keys |
|---|---|---|---|
| Karabiner-Elements | DriverKit | yes | all |
| kanata | DriverKit | yes | all |
| Mantle | DriverKit (wraps kanata) | yes | all |
| [hrm](https://github.com/wontaeyang/hrm) | none | yes | home row only |
| [BC64Keys](https://github.com/badcode64/BC64Keys) | none | no | all |
| Hyperkey | none | hyper only | Caps Lock and modifiers |
| Sleight | none | yes | all |

No column here is one Sleight wins on its own; every cell in its row appears
somewhere above it. The claim is the row, not any cell: the tools without a
driver each give something up, and the ones that give nothing up all want
DriverKit.

The column the table does not have is the one a driver wins: Karabiner works in
secure input fields, in games that read HID directly, and inside VMs. Sleight
does not, and cannot - see [Limitations](#limitations).

## Timeless tap/hold

There is no hold threshold. A key resolves to **hold** the moment another key is
pressed while it is down, and to **tap** otherwise, decided on release.

The usual approach picks a duration: too short and it misfires while you type
quickly, too long and every modifier press feels laggy. Neither happens if you
never look at the clock.

## It re-arms itself

macOS disables event taps on its own - after a slow callback
(`tapDisabledByTimeout`), on certain input (`tapDisabledByUserInput`), and around
sleep. Tools that do not handle this appear to work until one day the key silently
stops responding and only a relaunch fixes it.

Three independent recovery paths:

1. Both disable notifications are handled and re-enable the tap immediately.
2. Sleep and wake notifications re-verify it, and clear in-flight key state so a
   key held while the machine sleeps cannot come back as a stuck modifier.
3. A five second watchdog polls `CGEvent.tapIsEnabled` in case the first two are
   missed.

If the Mach port itself has gone bad, the tap is torn down and rebuilt.

`--test-kill-tap` disables the tap deliberately so this stays provable. Real
output, from `~/Library/Logs/Sleight.log`:

```
[01:14:22] WARN  TEST: forcibly disabled the tap - watchdog should recover it
[01:14:27] WARN  watchdog found the tap disabled
[01:14:27] INFO  tap re-enabled (re-arm #1)
```

## Any layout

Bindings are plain virtual key codes, so nothing is tied to a layout. The starter
config is picked from the attached keyboard: ANSI gets Caps Lock and Right
Option, ISO gets Caps Lock only - macOS has no separate AltGr, so on European
layouts the right Option key is how you type `@ \ { } [ ] | ~ €` - and JIS
additionally gets the two keys either side of the space bar, which do nothing at
all unless you use a Japanese input method.

Modifier keys work as binding targets too. They arrive as `flagsChanged` rather
than `keyDown`/`keyUp`, and left and right share the public modifier masks, so
Sleight reads the device-dependent bits to tell which physical key moved.

## Menu bar

Sleight runs as an accessory app: a menu bar item, no Dock icon. The menu shows
whether it is running and offers Settings, Pause, Open at Login and Quit.

Settings is one list. Each row is a key, what a tap sends, and what a hold turns
it into. Each field is a menu: pick a common key from the list, or choose **Press
a Key** and press the one you want. No key codes to look up either way.

Nothing takes effect until **Save**. **Revert** puts back whatever the window
opened with, and neither button closes the window. Applying edits as they were
made read nicely but meant a misclick on a picker silently changed how the
keyboard behaves, which is a poor trade in a window whose whole subject is what
your keys do.

Recording reads from the event tap rather than from the view, which is the only
reason Caps Lock and the modifiers can be bound at all - those never produce a
key press a view could receive. While a field is armed the engine swallows
everything, so the key being captured cannot also trigger its current binding or
type into whatever is behind the window.

`--no-menu` runs it headless instead, for running under a process supervisor. It
still needs a GUI login session - the tap belongs to one.

## Build

```
swift build                        # binary at .build/debug/Sleight
./Scripts/bundle.sh                # build/Sleight.app, ad-hoc signed
./Scripts/install.sh               # the above, then install and launch
swift Scripts/check-layout.swift   # check translations against the controls
swift Scripts/make-icon.swift 1.45 # rebuild the icon from Icon/source.jpg
```

`make-icon.swift` adds the two things a generated image will not have: a
continuous-curve corner rather than a plain radius, and the transparent margin
macOS expects around the 824-of-1024 icon body. The argument crops in, since an
image with comfortable margins of its own reads as a speck at 32 points.

`check-layout.swift` measures every translated string against the control that
has to hold it. Translations are not the length of the English they came from and
an overflow is truncated rather than reported: "Press a key" fits the key field,
and the same sentence in Japanese is half as wide again. Run it after touching
either the strings or the column widths.

### Accessibility permission and signing

Grant permission once:

```
./Scripts/create-signing-cert.sh   # once, ever
./Scripts/install.sh               # every time
```

The certificate is what makes it once rather than every time. An ad-hoc
signature's designated requirement is the cdhash:

```
$ codesign -d -r- Sleight.app
# designated => cdhash H"b9ee566b..."
```

That changes on every build, so the entry already sitting in Accessibility
settings stops matching the new binary. It keeps showing Sleight with its switch
turned on while the app is told it has no permission, and toggling it does not
help - the entry has to be removed and re-added. Signing against a certificate
gives a requirement that does not move:

```
designated => identifier "dev.sleight.Sleight" and certificate leaf = H"a29cf0fb..."
```

`install.sh` picks up the certificate if it exists, and falls back to clearing the
stale entry with `tccutil` if it does not.

A self-signed certificate is enough for development. Distribution needs a
Developer ID from Apple, since the tap needs Accessibility, and an
unsigned build cannot keep that permission across updates.

The menu bar item appears whether or not permission has been granted, and says so
when it has not. Waiting for permission before showing it left the app invisible
in precisely the case that needed explaining.

The `.app` bundle matters: macOS keys Accessibility permission off the code
signature. In my testing on macOS 26.1 a bare executable never appeared in the
permission list at all, so the bundle is not optional.

## Use

Nothing puts `Sleight` on `PATH`; run it from the build directory or the bundle.

```
.build/debug/Sleight --selftest   # state machine checks, no permissions needed
.build/debug/Sleight --sniff      # print the key code of every key you press
.build/debug/Sleight --verbose    # log every tap/hold decision
.build/debug/Sleight --no-menu    # run without the menu bar item
.build/debug/Sleight --dump-menu  # print the menu and exit
```

Settings is the usual way in. `--sniff` prints key codes from a terminal if you
would rather edit the file directly.

Settings writes to `~/.config/sleight/config.json`, which is also fine to edit by
hand:

```json
{
  "bindings": [
    { "keyCode": 57, "tapKeyCode": 53, "hold": "control" },
    { "keyCode": 61, "hold": "hyper" }
  ]
}
```

`hold` is one of `unchanged`, `control`, `option`, `command`, `shift`, `hyper`.
Omit `hold` for a tap-only key, or `tapKeyCode` for a hold-only key. A config that
fails to parse falls back to the defaults rather than leaving you with a dead
keyboard.

`unchanged` leaves the key doing its own job and only adds the tap. Use it for
keys the system watches directly:

```json
{ "keyCode": 55, "tapKeyCode": 102, "hold": "unchanged" }
{ "keyCode": 54, "tapKeyCode": 104, "hold": "unchanged" }
```

That is the arrangement popularised by [⌘英かな](https://github.com/iMasanari/cmd-eikana):
tapping left Command selects the roman input source and tapping right Command
selects kana, while Command itself is untouched. Swallowing the key and
re-applying its flag would cover ordinary shortcuts but break anything watching
the modifier itself, such as holding Command to page through the app switcher.

The keys it sends, 102 and 104, exist only on JIS keyboards but the codes work
from any layout, which is what makes this useful on an ANSI board. They do need a
Japanese input source to be enabled; with only one input source there is nothing
to switch to.

## Limitations

`CGEventTap` sits higher in the event stream than a driver does. That is the whole
trade, and some of it cannot be engineered away:

- Secure input fields, such as password prompts, bypass event taps entirely.
- Games that read HID directly will not see remapped keys.
- Remote desktop and VM clients that grab input do not see the remapping.
- Mouse clicks do not pick up hold modifiers. Clicks are watched, so a click
  while a key is held still resolves that key as a hold, but the click itself is
  passed through exactly as it arrived.
- The tap key is sent on release, not on press. That is inherent to deciding
  without a timer.
- A tap key cannot autorepeat. Holding a key bound to tap-Delete does nothing.
- Hold state is applied by rewriting flags on passing events, so an application
  that polls modifier state independently may disagree.

If you need remapping that works everywhere, use Karabiner and accept the driver.
Sleight is for the common cases where you do not.

## Status

Early, but usable. The state machine is covered by `--selftest`; the keep-alive
paths are exercised by hand with `--test-kill-tap`, since they need a real tap.

### Before this can be distributed

Builds are signed with a self-signed certificate, which is fine locally and
useless anywhere else: Gatekeeper refuses it on another Mac and it cannot be
notarized. An Apple Developer ID is the one remaining blocker, and it is a
membership rather than a piece of work.

Everything around it is ready. `Scripts/release.sh` builds, verifies, submits to
notarization, staples the ticket and reports what a downloader will see:

```
SIGN_ID="Developer ID Application: Name (TEAMID)" ./Scripts/release.sh
```

It refuses to submit anything it can already tell will be rejected, since
notarytool's account of why is slow to arrive and hard to read. The hardened
runtime is on, and the secure timestamp notarization requires now follows the
identity: self-signed builds cannot get one, so asking for it there would break
local installs.

Note that changing signing identity changes the designated requirement, so
Accessibility permission has to be granted once more after the switch. It then
stays granted across rebuilds, which an ad-hoc signature never manages.

## Prior art

[hrm](https://github.com/wontaeyang/hrm) reaches the same timeless conclusion for
home row keys, and is worth reading if that is what you want.

## License

MIT
