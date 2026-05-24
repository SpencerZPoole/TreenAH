# TreenAH

![Version](https://img.shields.io/badge/version-1.1.2-blue)
![WoW Interface](https://img.shields.io/badge/WoW%20Interface-20505-gold)
![License](https://img.shields.io/badge/license-MIT-green)

TreenAH is a World of Warcraft Classic Anniversary Auction House addon for building local market history over time. It records auction prices from the results you scan or browse, then makes that data available in tooltips, Auction House browse columns, tracked lists, and `/pc` price checks.

The addon is designed for players who want a lightweight, local-first view of recent market prices without depending on an external pricing service.

**Support:** If this addon helps your auction-house workflow, donations are optional and support continued maintenance, packaging, testing, and documentation.

[![Sponsor on GitHub](https://img.shields.io/badge/GitHub%20Sponsors-Donate-ea4aaa?style=flat&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/SpencerZPoole) [![Donate with PayPal](https://img.shields.io/badge/PayPal-One--time%20donation-00457C?style=flat&logo=paypal&logoColor=white)](https://paypal.me/mrpooley92)

## Features

- Records low auction prices from Auction House browse results.
- Builds recent historical averages for items TreenAH has seen.
- Adds optional price data to item tooltips.
- Adds an optional price column to the Auction House browse list.
- Supports passive browsing scans, single item scans, tracked list scans, fast full scans, and slower page-based full scans.
- Organizes important items into tracked lists, including an automatic Requests list for price-check requests.
- Provides `/pc` price checks for your own chat window, whispers, Battle.net friends, party, raid, guild, and say chat.
- Supports controlled auto-replies to `pc <item>` requests, with cooldowns and channel toggles.
- Includes in-game quick start and slash command help windows.
- Detects newer TreenAH versions seen from guild or group members.

## Compatibility

- Addon folder: `TreenAH`
- WoW interface target: `20505`
- Current addon version: `1.1.2`
- SavedVariables file: `TreenAHDB`

TreenAH is currently built for the `_anniversary_` World of Warcraft client folder. If Blizzard updates the client interface version, the addon may need a `.toc` metadata update before WoW stops marking it as out of date.

## Install

1. Download a release zip or clone this repository.
2. Place the `TreenAH` folder in your WoW addon directory:

   ```text
   World of Warcraft\_anniversary_\Interface\AddOns\TreenAH
   ```

3. Confirm this file exists:

   ```text
   Interface\AddOns\TreenAH\TreenAH.toc
   ```

4. Start or reload World of Warcraft.
5. Enable `TreenAH` from the AddOns screen if needed.

If the addon does not appear in the AddOns screen, the most common cause is an extra nested folder such as `TreenAH\TreenAH\TreenAH.toc`.

## Quick Start

1. Open the Auction House.
2. Browse normally to let TreenAH passively collect visible auction results.
3. Use manual scans when you want better data faster.
4. Use item tooltips, the browse price column, or `/pc <item>` to check prices after TreenAH has recorded data for that item.

In-game help is available with:

```text
/treenahhelp
/tahhelp
/treenahcommands
/tahcommands
```

## Slash Commands

| Command | Purpose |
| --- | --- |
| `/pc <item>` | Print a TreenAH price check in your own chat window. |
| `/pc party <item>` | Post a price check to party chat. |
| `/pc raid <item>` | Post a price check to raid chat. |
| `/pc guild <item>` | Post a price check to guild chat. |
| `/pc say <item>` | Post a price check to say chat. |
| `/pc <player> <item>` | Whisper a price check to a character. |
| `/pc bn:<BattleTag> <item>` | Send a price check to an online Battle.net friend. |
| `/tahpc <item>` or `/treenahpc <item>` | Alternate price-check commands. |
| `/treenahdata` or `/tahdata` | Open the recorded data browser. |
| `/treenahstats` | Print the number of items in the current market database. |
| `/treenahautoscan [on\|off]` | Enable or disable passive auto-scanning of visible Auction House results. |
| `/treenahautoshow [on\|off]` | Control whether the main panel opens automatically at the Auction House. |
| `/treenahautoreply [on\|off]` | Enable or disable automatic replies to price-check requests. |
| `/treenahautotrackrequests [on\|off]` | Control whether requested items are added to the Requests tracked list. |
| `/treenahthreshold <number>` or `/tahthreshold <number>` | Set the outlier filter threshold for unusually high prices. |
| `/treenahavgwindow <days>` or `/tahavgwindow <days>` | Set the recent average display window. |
| `/treenahversion` or `/tahversion` | Request a group or guild version check. |
| `/treenahcleardb` | Open the confirmation flow to delete recorded price history for the current server/faction. |
| `/treenahdebug [on\|off]` | Enable or disable debug messages. |

Price checks only work for items TreenAH has already recorded. If an item has no price data yet, scan it first.

## Troubleshooting

### TreenAH does not show up in the AddOns list

Check that the folder contains `TreenAH.toc` directly inside `Interface\AddOns\TreenAH`. If the path is `Interface\AddOns\TreenAH\TreenAH\TreenAH.toc`, move the inner folder up one level.

### WoW says the addon is out of date

The `.toc` file targets interface `20505`. If the client has moved to a newer interface version, enable out-of-date addons temporarily or update the interface value after confirming the addon still loads correctly.

### Tooltips or `/pc` show no price

TreenAH only reports data it has recorded locally. Open the Auction House and run a scan for the item or let passive browsing collect results over time.

### Auto-replies are too quiet

Check `/treenahautoreply`, the auto-reply channel settings in the TreenAH options panels, and the built-in cooldown behavior. Public and group channels are intentionally more conservative than whispers.

### Fast Full Scan is not ready

The WoW Auction House API controls when fast full scans are available. Try again shortly or use a slower scan mode.

## Development

The addon is intentionally organized by responsibility:

- `Core/` contains startup, event registration, slash commands, and shared utilities.
- `Data/` contains saved variable and tracked item data handling.
- `Systems/` contains Auction House scanning, price checks, and version checks.
- `UI/` contains panels, tooltip hooks, browse column behavior, and in-game help.
- `TreenAH.toc` defines addon metadata and file load order.

This repo does not currently use a Lua test runner. The primary validation path is source review, packaging checks, and in-game loading in the target WoW client.

## Packaging

Create a release zip from the repository root:

```powershell
.\scripts\package-release.ps1
```

The script reads the addon version from `TreenAH.toc` and writes a zip to:

```text
dist\TreenAH-v1.1.2.zip
```

The zip contains a top-level `TreenAH/` folder so it can be extracted directly into `Interface\AddOns`.

## Contributing and Support

When reporting an issue, include:

- TreenAH version.
- WoW client flavor and interface version.
- What you were doing in the Auction House.
- Any Lua error text.
- Whether the issue happens after disabling other Auction House addons.

Pull requests should keep addon behavior understandable, avoid unnecessary dependencies, and preserve the existing source layout unless a structural change is clearly justified.

