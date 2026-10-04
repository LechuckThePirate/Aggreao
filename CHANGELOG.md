# Changelog

## 1.1.2

- Fix: Lua errors in the "Other mobs" section ("attempt to compare ... a secret string value"). The game
  hides the role, class and name of whom an enemy is attacking from addons in combat; they are now
  never compared, joined to text or tested. A hidden name is shown as it is, without color or icon.
  The same care is taken with every other value that comes from a unit.
- Fix: "attempt to perform numeric conversion on a secret number value" when measuring a line of the "Other
  mobs" section: a text field that has shown a hidden name answers its size with a hidden number, so the
  width is now measured on a field of its own that never gets one.
- Fix: the mob that is your target is told apart from the others by the game (not by its GUID).

## 1.1.1

- Fix: "Show other mobs in combat" raised an error in combat on clients that hide whom a mob is
  attacking from addons ("attempt to perform boolean test on a secret boolean value"). Those lines
  now simply don't say whether the mob attacks you, a pet or a player.

## 1.1.0

- Fix: the alert sounds when you take the aggro from someone else (your pet, say) even if your threat
  jumped over the warning zone between two updates of the game; and it no longer sounds when the pet
  takes the aggro back while your threat is still high. It re-arms only when your threat drops well
  below the threshold.
- Faster "about to pull" alert: your own threat is checked every 0.1 s on its own (it used to wait for
  the window to redraw, up to a quarter of a second), and the window redraws 0.05 s after a threat
  event instead of 0.1 s. The game's own threat updates still set the limit.
- New: "Show other mobs in combat" (Preferences, off by default): under the list of your target,
  one line per other mob you are fighting -- its name and whom it is attacking, with your own
  threat on it where the client has it; the ones attacking you in red. A shield marks the tank
  holding a mob and a paw a pet (alone, your pet is your tank). Needs enemy nameplates.

## 1.0.0

First public release.

- Aggro window for the target: who has the aggro and how close the others are, in order, with class
  colors and role icons (tank, healer, dps). Movable, lockable, scale and opacity.
- Pets get a paw-print icon in the list (with the role icons).
- Title bar "Aggreao!!" with a padlock (lock the position) and a close button; the window is
  click-through in combat.
- Out of combat the window says "Not in combat" (no made-up players); preference to hide it then.
- Sound alert (and optional red border) when you are close to taking the aggro; threshold and sound
  chosen in the preferences.
- Preferences window (per character or shared), minimap button and welcome window, as in
  Completao!! and Embolsao!!.
- Initial skeleton: TOC for Retail, TBC Anniversary, Classic Era and Forever,
  `/aggreao` (`/agg`), saved variables, Spanish/English locale, tests and CI.
