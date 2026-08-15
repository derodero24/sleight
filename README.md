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

## Build

```
swift build           # binary at .build/debug/Sleight
./Scripts/bundle.sh   # build/Sleight.app, ad-hoc signed
```

The `.app` bundle matters: macOS keys Accessibility permission off the code
signature, and macOS 26.1 has a bug where a bare executable never appears in the
permission list. Distribution additionally needs a Developer ID certificate, since
Launch Services requires one for `CGEventTap` with Input Monitoring.

## Use

```
Sleight --selftest   # state machine checks, no permissions required
Sleight --sniff      # print the key code of every key you press
Sleight --verbose    # log every tap/hold decision
Sleight              # run
```

Run `--sniff` first if you are binding something unusual. Third-party keyboards do
not always report the codes you would expect.

Config lives at `~/.config/sleight/config.json` and is written on first run:

```json
{
  "bindings": [
    { "keyCode": 57, "tapKeyCode": 53, "hold": "control" },
    { "keyCode": 61, "hold": "hyper" }
  ]
}
```

`hold` is one of `control`, `option`, `command`, `shift`, `hyper`. Omit `hold` for a
tap-only key, or `tapKeyCode` for a hold-only key. A config that fails to parse
falls back to the defaults rather than leaving you with a dead keyboard.

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

Early. The state machine and the keep-alive logic are tested and working; there is
no user interface yet, so configuration is a JSON file.

## Prior art

Independently implemented. [hrm](https://github.com/wontaeyang/hrm) demonstrates the
same timeless approach for home row keys; note that it currently ships without a
license file, so its code cannot be reused.

## License

MIT
