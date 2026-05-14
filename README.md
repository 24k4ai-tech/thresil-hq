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

Live on Ethereum mainnet:

- Launcher: `0x124A3eC8a2ccBab1523e998aC851474824529180`
- Token: `0x1De9c0F378f66F6E7b5699dC5C2F18E19d567AbD`
- Last-buyer pot: `0x949B4B5B33df62B26CE9aD97102C56FF8d3dDBC6`
- Penalty draw: `0xb5Cf9Dc1DA57Dd87EE7Db2962AfDcC143f0AF26C`
- LP club: `0x4B7b39D6B8702888E18148109Becc4734A880659`
- V4 hook: `0x6C679d3f54366f2431393c0824F922CbDFAa05cc`
- API tax wallet: `0x830EE35dC25Bfc3b9E93470c7BE1d4929F888355`
- Mainnet v4 pool id: `0x76316794f14c0d13a5688dc4d5333ed06e802ea2889f9537a205c5ef7375a461`

Launch:

- Launched at block `25094022`, timestamp `2026-05-14 14:38:11 UTC`.
- Launch transaction: `0x09018cccf53da8aa844892483c0bcb0657751a18289f68270ffc0a9dea0701f1`
- Dev seed buy: `0xc3635edf88eeee43360e7e1d09966f364b7b65849703ffc3ce28fc213f817cba`
- Pool initialization: `0x4ae5cc9225ec542c6da5d4de9d8eebe221bffd17e839e27e4358b133208c9a8c`
- Seed LP mint: `0xeed8cac0c7e650fbd148ac5b5f1a0c94b8b043da2ff83bcd37df0ec9aadc13c9`
- Seed LP NFT `272160` was minted to `0x000000000000000000000000000000000000dEaD`.

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
