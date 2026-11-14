# VoidBounty Changelog

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
