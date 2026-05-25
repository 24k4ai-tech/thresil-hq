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

- Launcher: `0x828318182b294E9AFf2437e7Dc4810Aa955Bb764`
- Token: `0xcB16cA9d5c6F9090A1b56D29ACb31D764bc2ed7c`
- Last-buyer pot: `0x107E0b771877e560B846AEcA0cE3b15D83592091`
- Penalty draw: `0x350E881320d890B5EdD83be5c24CE0EDEf185f55`
- LP club: `0x78893A2C26F57849B163f09D11f404d9E23A593e`
- V4 hook: `0xfBaFDa29fc1Ec863C10481270E24FEB1853CC5cc`
- Hook deployer: `0x69F1d0D13F48B8186dc418c1189B42E9926402Ae`
- API tax wallet: `0x830EE35dC25Bfc3b9E93470c7BE1d4929F888355`
- Mainnet v4 pool id: `0x17cb7ce5b84d43b804145ece8cf5c81c6650cb1cd229474a6901124bd4518270`

Launch:

- Staged deploy txs:
  - Launcher: `0x15e6e30bcbd72da8885d60af1fa079660caaf3c6c22eaef93a6b55f0436f5fc6`
  - Last-buyer pot: `0x61af714f5432717ea0fe2c4a40c5c9c6bffbc9d27743bf0388c929a6f4ae4ac1`
  - Penalty draw: `0xacbdcdb138eb393464a79b85320f35906e1db415443e4b73b220957f903035c4`
  - Hook deployer: `0x58ed2ef6296317aad20a7905b75bf3f1f86c273263e886a423524c19fe9a7aa5`
  - Hook deploy call: `0x437e63ca34d25d88c0525bf224498e308328213f632a08c098c7d1a2434ead8e`
  - LP club: `0xb0df6112f9a92b76718f952f4896a00f49a78cd28abdbe82a3d976033240c5d3`
- Launched at block `25117559`, timestamp `2026-05-17 21:20:11 UTC`.
- Launch transaction: `0x4fa5e68f138b7260cef22083c6af5c562ad045dfab123c56bfe8f13cecf4fad2`
- Dev seed buy: `0xdc60ef6db00642db32c715ba21db596e8e7c914842915dc0b5dc3be1dfaaa533`
- Pool initialization: `0x03ddfd10cc1b30d65b98a810c6b3300cfb6e74080ffe7112784b0de71890f7d6`
- Seed LP mint tx: `0x8f16364fc4c7ff1b572e5811c1dfd3a27dbf3c7d2cf55ba536542be14e13791f`
- Seed LP recipient: `0x000000000000000000000000000000000000dEaD`

Current build focus:

- `src/FTMonsterArcadeLauncher.sol` keeps the mint rail first and drives a 17 ETH gross SATO-style reserve curve.
- `src/FTMonsterLastBuyerPot.sol` pays the last qualifying buyer when the timer expires and the next onchain touch settles.
- `src/FTMonsterPenaltyDraw.sol` burns 777X for weighted draw entries, locks a future block seed after the round ends, and pays 30% of the armed pot.
- `src/Oracle777FlapPenaltyVault.sol` is the Flap-focused version: Flap launches the token, the custom vault receives BNB tax, users voluntarily send 777X to the dead address to shoot, and each settled 17-minute round requests Chainlink VRF before paying 30% of the available pot.
- `web/` contains the live `777x.space` homepage and the How To Play page.

## Flap Penalty Mode

The new Flap route does not deploy the token from this repository. Create the token on Flap, then use the deployed `Oracle777FlapPenaltyVaultFactory` as the custom vault factory.

BSC deployment:

- Network: BNB Smart Chain mainnet, chain id `56`
- Deployer: `0xB71Eef614Ee8619Ea14735BA39187dc847b49E63`
- Factory: `0xb5Cf9Dc1DA57Dd87EE7Db2962AfDcC143f0AF26C`
- Factory deploy tx: `0xc7ce29ffa656aad5f3f6812ef5544bcd5b157f82db381dc27d09e2deb7c22751`
- VRF coordinator: `0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9`
- VRF subscription id: `30724563043082722396497695814959597692086994674352818468284068607141634353807`
- VRF key hash: `0xeb0f72532fed5c94b4caf7b49caf454b35a729608a441101b9269efb7efe2c6c`
- VRF subscription native funding tx: `0x458fda82db16e79913fb51b026bc6788ec924fabf8e1dae7dd443a2a036dbbcf`
- Factory source: Sourcify exact match. BscScan API verification is not submitted because no BscScan/Etherscan API key is configured locally.

Target mechanics:

- Flap token tax target: 3% buy / 3% sell.
- First 77 minutes: one third of vault inflow goes to the dev/API wallet.
- After 77 minutes: dev/API share ends automatically; new vault inflow remains in the penalty pot.
- Users voluntarily call `shoot(uint256)` to transfer 777X to `0x000000000000000000000000000000000000dEaD`.
- Each round lasts 17 minutes.
- Each settled round requests Chainlink VRF and pays 30% of the available BNB pot.
- `poke()` and incoming BNB tax can request VRF for a ready round; the VRF callback pays normal winners automatically.
- The created Vault must be added as a consumer on the configured Chainlink VRF v2.5 subscription.
- A Vault cannot be created without nonzero VRF coordinator, subscription id, and key hash. This avoids deploying a game that can accept shots but never settle.

Create a VRF subscription by wallet transaction, if one does not already exist:

```powershell
$env:VRF_COORDINATOR="<bnb_chainlink_vrf_v2_5_coordinator>"
$env:VRF_INITIAL_FUNDING="0"
forge script script/CreateOracle777VrfSubscription.s.sol:CreateOracle777VrfSubscription --rpc-url $env:BNB_RPC_URL --broadcast
```

Deploy factory:

```powershell
$env:VRF_COORDINATOR="<bnb_chainlink_vrf_v2_5_coordinator>"
$env:VRF_SUB_ID="<subscription_id>"
$env:VRF_KEY_HASH="<gas_lane_key_hash>"
forge script script/DeployOracle777FlapPenaltyVaultFactory.s.sol:DeployOracle777FlapPenaltyVaultFactory --rpc-url $env:BNB_RPC_URL --broadcast
```

After Flap creates the concrete Vault, add that Vault as a VRF consumer:

```powershell
$env:FLAP_PENALTY_VAULT="<vault_created_by_flap>"
forge script script/AddOracle777VrfConsumer.s.sol:AddOracle777VrfConsumer --rpc-url $env:BNB_RPC_URL --broadcast
```

## Verification Status

- GitHub `main` is the public source for the active site-and-protocol build.
- Sourcify mainnet verification:
  - Exact match: Launcher, Token, Last-buyer pot, Penalty draw, LP club.
  - Match: V4 hook, HookDeployer.
- Etherscan mainnet verification is complete for Launcher, Token, Last-buyer pot, Penalty draw, LP club, V4 hook, and HookDeployer.

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
