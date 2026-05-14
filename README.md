# Oracle777

Open-source repository for the `Oracle777` / `777X` arcade contracts, website, tests, and deployment helpers.

## Overview

- Token name: `Oracle777`
- Token symbol: `777X`
- Website: [https://www.777x.space/](https://www.777x.space/)
- X: [https://x.com/Oracle_777X](https://x.com/Oracle_777X)

This repository contains:

- Solidity contracts in `src/`
- Foundry tests in `test/`
- Deployment and verification scripts in `script/`
- Static website in `web/`

## Mainnet Addresses

Current build focus:

- `src/FTMonsterArcadeLauncher.sol` keeps the mint rail first and drives a 17 ETH gross SATO-style reserve curve.
- `src/FTMonsterLastBuyerPot.sol` pays the last qualifying buyer when the timer expires and the next onchain touch settles.
- `src/FTMonsterPenaltyDraw.sol` burns 777X for weighted draw entries, locks a future block seed after the round ends, and pays 30% of the armed pot.
- `web/` contains the live `777x.space` homepage and the How To Play page.

## Verification Status

- The arcade contracts in this repository are the active site-and-protocol build.

## Local Development

Requirements:

- Foundry
- Node.js
- PowerShell on Windows

Install dependencies:

```bash
forge install
npm install
```

Run tests:

```bash
forge test -q
```

## Website

The production site is a static Cloudflare Pages deployment sourced from `web/`.

Useful commands:

```bash
npm run cf:pages:deploy
npm run cf:ship
```

Create a local `.env` from `.env.example` before using deploy scripts.

## Notes

- `FTMonsterArcadeToken` and `FTMonsterArcadeLauncher` expose `website`, project image, and repository metadata on-chain.
- The repository intentionally excludes `.env`, deployment secrets, generated build output, and local cache directories.
