# Sleight

Tap/hold key remapping for macOS, without a driver.

Give a key two jobs: tap it to send one key, hold it to become a modifier.

```
Caps Lock      tap -> Escape     hold -> Control
Right Option   tap -> (nothing)  hold -> Control+Option+Shift+Command
```

Sleight uses `CGEventTap`, which is built into macOS. There is no kernel
extension, no DriverKit system extension, and no virtual HID device to install or
approve.

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
| Hyperkey / Superkey | none | hyper only | Caps Lock and modifiers |
| Sleight | none | yes | any key |

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

`--test-kill-tap` disables the tap deliberately so this stays provable:

```
TEST: forcibly disabled the tap - watchdog should recover it
tap disabled by user input - re-arming
tap re-enabled (re-arm #1)
```

## Any layout

Bindings are plain virtual key codes, so nothing is tied to a layout. The starter
config is picked from the attached keyboard: ANSI and ISO get Caps Lock and Right
Option, JIS additionally gets the two keys either side of the space bar, which do
nothing at all unless you use a Japanese input method.

Modifier keys work as binding targets too. They arrive as `flagsChanged` rather
than `keyDown`/`keyUp`, and left and right share the public modifier masks, so
Sleight reads the device-dependent bits to tell which physical key moved.

## Menu bar

Sleight runs as an accessory app: a menu bar item, no Dock icon. The menu lists
the active keys and offers Settings, Pause, and Open at Login.

Settings is one list. Each row is a key, what a tap sends, and what a hold turns
it into. **To set a key you click the field and press it** - no key codes to look
up.

Edits reach the running engine straight away, so a binding can be felt before
committing to it, but nothing is written to disk until Done. Cancel puts back
whatever the window opened with. A wrong binding can make the keyboard awkward to
use, which is the worst moment to be retyping old values by hand.

Recording reads from the event tap rather than from the view. That is what makes
it possible to bind Caps Lock and the modifiers at all, since those never produce
a key press a view could receive. The engine pauses while a field is armed, so
capturing a key does not trigger whatever it is currently bound to.

`--no-menu` runs it headless instead, which is useful over SSH or under a process
supervisor.

## Build

```
swift build                        # binary at .build/debug/Sleight
./Scripts/bundle.sh                # build/Sleight.app, ad-hoc signed
./Scripts/install.sh               # the above, then install and launch
swift Scripts/check-layout.swift   # check translations against the controls
```

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
signature, and macOS 26.1 has a bug where a bare executable never appears in the
permission list at all.

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
- Remote desktop and VM clients that grab input are unaffected.
- Mouse clicks do not pick up hold modifiers, since only keyboard events are tapped.
- Hold state is applied by rewriting flags on passing events, so an application
  that polls modifier state independently may disagree.

If you need remapping that works everywhere, use Karabiner and accept the driver.
Sleight is for the common cases where you do not.

## Status

Early, but usable. The state machine and the keep-alive logic are covered by
`--selftest`.

### Before this can be distributed

Builds are signed with a self-signed certificate, which is fine locally and
useless anywhere else: Gatekeeper will refuse it on another Mac, and it cannot be
notarized. Moving to a Developer ID is the blocker for releasing anything, and
an unsigned build cannot keep Accessibility permission across updates.

`Scripts/install.sh` already takes a `SIGN_ID`, so the mechanism is in place. What
is left is the Apple Developer Program membership and notarization; the hardened
runtime is already on (`bundle.sh` passes `--options runtime`). Note that changing the signing identity changes the designated
requirement, so Accessibility permission has to be granted once more after the
switch.

## Prior art

Independently implemented. [hrm](https://github.com/wontaeyang/hrm) demonstrates the
same timeless approach for home row keys; note that it currently ships without a
license file, so its code cannot be reused.

## License

MIT
