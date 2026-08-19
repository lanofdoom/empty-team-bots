# LAN of DOOM empty team bots plugin

> **wip:** issues when loading maps without nav meshes.

A SourceMod plugin that keeps bots on the team with fewer humans.

# Installation

Copy `empty_team_bots.smx` to your server's
`css/cstrike/addons/sourcemod/plugins` directory.

# Behavior

Always on, no commands or votes. When every human is on the same team, the
empty team is filled with bots -- one more than the humans they face, and
never fewer than 3. With humans on both teams there is already a game, so no
bots are added.

The plugin re-evaluates on round start, team change, connect, and disconnect.
