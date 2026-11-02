# QAI usermod (skeleton)

This is a pass-through skeleton. It changes no AI behavior. Its only job is to show
that LOUD loads a usermod hook from the usermods folder.

## Install (Proton, Ubuntu)

1. In the LOUD launcher, make sure **Documents mods enabled** is on.
2. Copy the `usermod/QAI` folder from this repo into the game's usermods folder:

   `<prefix>/pfx/drive_c/users/steamuser/My Documents/My Games/Gas Powered Games/Supreme Commander Forged Alliance/usermods/QAI`

   Create `usermods` if it doesn't exist. `<prefix>` is the Proton prefix for app 9420.
3. Start a skirmish with AI slots set to LOUD.

## What to look for

The game log should contain one line from QAI:

- `QAI: hook loaded; base AddGlobalBaseTemplate found, passing through unchanged`

If it says `NOT found`, the hook loaded before the base file. Report that, with the log line.

## Uninstall

Delete the `QAI` folder from `usermods`. Nothing else was changed.

## Attribution

This mod is built on the LOUD AI, by the LOUD Project and its contributors
(https://github.com/LOUD-Project/Git-LOUD). The LOUD team has confirmed that LOUD AI
code may be used when its authorship is credited publicly. This mod does not include
or redistribute LOUD files. It hooks into them at runtime.

The bundled LOUD mods (for example Total Mayhem, BlackOps, and 4th Dimension) are not
covered by LOUD's permission. This mod does not use their files.
