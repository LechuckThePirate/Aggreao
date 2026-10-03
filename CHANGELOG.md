# Changelog

## Unreleased

- New: "Show other mobs in combat" (Preferences, off by default): under the list of your target,
  one line per other mob you are fighting -- its name and whom it is attacking, with your own
  threat on it where the client has it; the ones attacking you in red. Needs enemy nameplates.

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
