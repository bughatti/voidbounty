# VoidBounty - World PvP Enemy Alert & Kill List

**Works on:** WoW Forever

> **New: VoidNet.** All six Void network addons (VoidLayer, VoidSweep, VoidQuest, VoidGather, VoidBounty, VoidDungeon) now share one channel on WoW Forever, so you reach more players. Versions from before November 10, 2026 can't share at all: please update (the CurseForge app does it for you).

**Beta:** new, and it gets better with every player who runs it: each one is another pair of eyes for your side.

**Know when enemy players are near, remember who killed you, and see who's hunting your side.**

World PvP in WoW Forever: VoidBounty warns you when enemy players are around, puts whoever kills you on a list, turns the warning red when they come back, and shares what you see with the other VoidBounty players of your faction.

**Two kill lists:** **Blood debts**, the enemy players who killed you, and **Your kills**, the ones you killed.

---

## Features

### The nearby warning
- A red box near the top of the screen while enemy players are around: **"3 Alliance nearby: Warrior 36, Mage 34, Druid 30"**. It **flashes** for a few seconds when someone shows up (**Flash the warning** in Settings turns that off)
- A player who killed you gets a **red line of their own**, with a warning sound when they show up, and the box keeps flashing while they're near
- Enemy players are seen from nameplates, your target and your mouse, in the open world (battlegrounds hide who players are, so it stays quiet there)
- Drag the box to move it; it stays where you put it, even after a restart

### Blood debts: who killed you
- When an enemy player kills you, VoidBounty reads the death recap and puts the killer on your **Blood debts** list: how many times, where, when you last saw them
- **Mark my target** adds anyone you choose
- **Unmark** takes them off; they come back if they kill you again

### Sightings and tracking
- **Danger here:** how many enemy players were seen in your zone in the last 15 minutes, and their levels
- **Sightings:** enemy players per zone and a feed of the last 30 minutes, yours and your side's
- **Track** a player: a sound and a chat line the moment you, or any VoidBounty player of your side, sees them

### Most wanted
- When a VoidBounty player is killed by an enemy player, your side hears "killed by X". **Most wanted** ranks who's killing your side this week: **Known, Dangerous, Feared, Dread**
- Only the killer is named. Nobody stores who died

### Your kills
- Every honorable kill on an enemy player in the open world is listed under **Most wanted**: who it was, their class and level, when and where. It's your own list, kept on your character; nothing about it is sent anywhere
- An honorable kill means you helped kill them (the game gives the whole group credit), not always the killing blow
- Battleground and dungeon kills are counted on their own, not listed

### Bounties: coming soon
- Wanted posters on the players who killed you, hunters who take them on, and a reward paid in basic vendor goods (never gold). Being tested now; it arrives in an update. The players who kill you today will still be on your list

### VoidNet: one network for every Void addon
- VoidBounty, VoidLayer, VoidSweep, VoidQuest, VoidGather and VoidDungeon players of your faction find each other through **one** hidden chat channel whose name and password change every hour, with backups. Messages go by hidden addon whispers
- **Hard to break:** if someone takes the channel over, bans or kicks Void players or changes its password, everyone moves to a backup within about a minute and a half, and sharing carries on by whisper with the Void players you heard from lately. That player is ignored for 24 hours (a report from others counts only when 3 different Void players saw it). Nothing is shown as a list of names
- **Kept on your computer:** the Void players you heard from in the last 2 hours (names and a time, deleted after 2 hours, never shown or shared) and players marked for attacking the channel (24 hours)
- What's shared: an enemy player's name, the game's ID for that player, level, class, guild, zone and a rough area of the zone (never a live position), at most once every 3 minutes per player. **Share my sightings** and **Share my deaths** in Settings turn each off
- The Void **Players online** box shows **VoidNet**: every Void addon player of your side online, each counted once
- Older VoidBounty versions are still reached through the old channel, which goes 30 days after the last one updates

### Helping other players change layer
- VoidBounty carries the Void layer helper: when a Void player on your layer asks (from VoidLayer or VoidSweep), you send them a quick group invite that ends on its own, only while you're solo and out of combat. A short pop-up says so once
- **Help others change layer** in the Settings tab turns it off. It's one switch for every Void addon, the same as the hub's **Help Void layer hopping**

---

## Slash Commands

You rarely need them: open it from the Void hub button on the minimap.

| Command | What it does |
|---|---|
| `/vbounty` | Open or close the window |
| `/vbounty mark` | Put your target on Blood debts |
| `/vbounty test` | A made-up enemy "Test Dummy" near you, to see the warning (`/vbounty untest` removes it) |
| `/vbounty net` | Check that messages to other Void players get through |

---

## Getting Started

1. Install with the CurseForge app, or copy the `VoidBounty` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Log in. The warning works right away; the more players of your side run it, the more it sees.
3. Open the window from the Void hub button on the minimap, or `/vbounty`.

---

## Good to know

- **The open world only.** Battlegrounds and arenas hide who players are, so VoidBounty stays quiet there.
- **A killer goes on Blood debts when VoidBounty saw them first** (a nameplate, your target or your mouse). Turn enemy nameplates on to catch the most.
- **Settings are per character.**

---

## Compatibility

- **WoW Forever**
- Standalone: nothing else to install

---

*Part of the Void addon family by Vede · MIT licensed · [Source & bug reports](https://github.com/bughatti/voidbounty) · [All Void addons](https://www.curseforge.com/members/bughatti/projects) · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more at [tinkerline.io](https://tinkerline.io) · [Discord](https://discord.gg/7ZHmx7zMDh)*
