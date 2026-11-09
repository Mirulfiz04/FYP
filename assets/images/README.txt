PUT YOUR LOGIN HERO IMAGE HERE
==============================

Save your illustration in THIS folder with the exact name:

    login_hero.png

The login screen (lib/screens/auth/login_screen.dart) loads it
automatically:

    assets/images/login_hero.png

Tips
----
- Recommended: a transparent PNG (the screen shows it ~170 px tall).
- A square image around 400x400 px or larger looks best.
- Until login_hero.png exists, a branded placeholder is shown instead,
  so the screen always looks complete.
- After adding/replacing the file, do a full app restart (not just hot
  reload) so Flutter re-bundles the new asset.

To use a different file name, change the path in login_screen.dart
(the `_HeroImage` widget).
