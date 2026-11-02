# QAI

QAI is a style and configuration layer for LOUD, the AI modification for Supreme
Commander: Forged Alliance. The long-term goal is that a player describes a play style
in plain language, and the LOUD AI plays that way. The current milestone is a vertical
slice: show that an external config file measurably changes LOUD's in-game behavior.
The name is a nod to the Quantum AI from Supreme Commander lore, which bends other AIs
to new purposes. Here, LOUD is the AI being bent, and it stays on the player's side.

## Credit

QAI is built on the LOUD AI, by the LOUD Project and its contributors
(https://github.com/LOUD-Project/Git-LOUD). The LOUD team has confirmed that LOUD AI
code may be used when its authorship is credited publicly. QAI does not include or
redistribute LOUD files, and it does not use the bundled mods (such as Total Mayhem,
BlackOps, and 4th Dimension), which LOUD does not license.

## License

Our original code is released under the Unlicense (see LICENSE). That covers only the
contents of this repository. It does not cover LOUD or the bundled mods.

## Status

Phase 0 (discovery) is done, and its decisions are in `docs/discovery.md`. The QAI
usermod skeleton (`usermod/QAI`) is a pass-through hook. It changes no AI behavior yet.
