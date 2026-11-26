# VoidBounty Changelog

## 0.4.4 — 2026-11-26

- **Fixed: Void players losing each other every hour (WoW Forever).** On the hour, every player's addon checked the new hour's shared channel at once. With 200+ players the channel's owner couldn't answer them all in time, so most addons gave up on it and moved to backup channels: within minutes everyone was spread over 4 channels, sharing only with a slice of the others, and the players box dropped (230 to 65 on the Alliance side). Now a few players check right away and the rest later, spread out, so everyone stays together. A channel taken over by someone else is still left within minutes. Also: the players box shows the right count a minute after the hour instead of five, and a channel's owner is no longer missed in channels of 300+ players.

## 0.4.3 — 2026-11-25

- **VoidHub window (WoW Forever):** right-click the VoidHub minimap button (or type /vhub) for every Void addon in one window: quests, layers, gear, gold, professions, combat, dungeons and more, each drawn from its own addon, with a Start page for what to do right now. Addons you don't have show a screenshot and how to get them. Shift + right-click opens Copy settings from another character. It comes inside every Void addon: nothing extra to install.

## 0.4.2 — 2026-11-24

- **Layers work again after the game's November 20 update (WoW Forever).** The update gave every NPC a number of its own, so the layer read off the NPCs around you kept jumping. The layer engine every Void addon shares (from VoidLayer 0.6.0) now names your layer itself and lets the game keep the name right: a world refresh or a hop gives you a new name, Void players who turn out to be on one layer take one name, and a layer hop turns down an invite from a helper who's on your layer already.

## 0.4.1 — 2026-11-17

- **Layer helping finds players faster (WoW Forever).** A layer question now reaches the Void players it asks in about a second instead of eleven, so Refresh and hops see the other layers right away. Same message rate over time, well under the game's limit.

## 0.4.0 — 2026-11-17

- **VoidNet: one hidden channel for every Void addon (WoW Forever).** VoidLayer, VoidSweep, VoidQuest, VoidGather, VoidBounty and VoidDungeon now share ONE channel instead of one each. The Void players box shows **VoidNet** (every Void addon player online, each counted once) with **Layer helpers** under it. Players on an older version are still reached through the old channel, which goes away 30 days after the last of them updates.
- **Harder to grief:** the channel name changes every hour, with backups. If someone takes the channel over, bans or kicks Void players, or changes its password, every Void addon moves to the backup and ignores that player for 24 hours (a report from others counts only when 3 different Void players saw it). Nothing is shown as a list of names.
- **You can now help other players change layer** (WoW Forever): when a Void player on your layer asks, you send them a quick group invite, only while you're solo and out of combat. A short pop-up says so once. Don't want it? Turn it off with a box in the Settings tab (the same switch for every Void addon).

## 0.3.6 — 2026-11-16

- **Fixed: the VoidGPS search bar drew over the VoidBounty window.** The window now sits with the other Void windows, opens in front, and comes forward when you click it.

## 0.3.5 — 2026-11-14

- **Fixed: players split into different channels every hour.** When the channel's owner left at the hourly switch, the game made the next player a moderator, and 0.3.4 took that as a griefer and moved away from the old owner. Moderator changes no longer count, only bans, kicks and password changes.

## 0.3.4 — 2026-11-14

- **Sharing is much harder to break.** VoidBounty's hidden sharing channel could be taken over: whoever joins it first owns it and can ban players, which shut a player out for the rest of the day. Now:
  - the channel has a code name and changes every hour, so a ban lasts an hour at most;
  - VoidBounty checks who owns the channel. If the owner isn't a VoidBounty player, or the game won't let you in, everyone moves to a backup channel within about a minute and a half;
  - when a VoidBounty player who owns the channel logs out, it hands the channel to another VoidBounty player, so a stranger doesn't get it;
  - **sharing carries on without the channel:** the channel only finds players, so even if you're shut out, VoidBounty keeps sharing with the players it heard from in the last hour;
  - anyone who bans or kicks a player from the channel, changes its password or hands out moderator rights is avoided for the rest of your session: VoidBounty never trusts them, never shares with them and never hands them the channel, and if they own it, everyone leaves it at once.
- The channel's join and leave lines stay out of your chat.
- Bans, owner changes and password changes on the channel are written down, with who did them (`/vbounty net` shows the owner).

## 0.3.3 — 2026-11-12

- **Fixed: a side of a box could be missing**, e.g. the right line of the recipes box and its buttons when the game window is an odd number of pixels wide. Every Void box now always shows all four border lines.

## 0.3.2 — 2026-11-12

- **The warning box moves with a plain drag** (it needed Shift) and stays where you put it, even after a restart; the other VoidBounty boxes too.
- **The players-here box:** its tooltip no longer covers the box while you drag it, and it opens above or below the box depending on where the box sits on screen.
- The Void hub's info window now stays where you put it.

## 0.3.1

- **Your kills:** every honorable kill on an enemy player in the open world is listed under Most wanted, with who it was, their class and level, when and where. Your own list, never sent anywhere. Battleground and dungeon kills are counted on their own.
- **The warning is a red box now, and it flashes** for a few seconds when an enemy player shows up, and the whole time a player who killed you is near. **Flash the warning** in Settings turns the flashing off.

## 0.3.0

First public release.

- **Nearby warning:** a line near the top of the screen while enemy players are around, red for a player who killed you, with a sound when they show up.
- **Blood debts:** whoever kills you goes on your list by itself, with how often and where. Mark my target adds anyone.
- **Sightings and Danger here:** enemy players per zone in the last 15 minutes and a 30-minute feed, yours and your side's.
- **Track:** a sound and a chat line when you, or any VoidBounty player of your side, sees a player you track.
- **Most wanted:** who's killing your side this week, from the deaths VoidBounty players share (only the killer is named).
- **Its own network** per faction, with a daily password.
- **Bounties are coming soon:** wanted posters, hunting and tribute in vendor goods are being tested and arrive in an update.
