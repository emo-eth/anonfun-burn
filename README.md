# DeterministicUpgradeableFactory

- Deploys deterministic ERC1967 UUPSUpgradeable proxies using CREATE2
- (For deploying the UniV3Rebuyer to Base, and the SignatureValidator to OP Mainnet)

# SignatureValidator

- Validates ERC1271 signatures via an EOA-signed EIP712 signature of a recent blockhash
- Owner-configured signer
- (For Farcaster address linking)

# UniV3Rebuyer

 
- Collects fees from a default Clanker LPLocker
- Can collect fees for other owned Clanker LPLockers, including V2
- Can accept ETH and convert it to WETH
- Once per time period, can swap WETH for the token in the pool and burn the LP tokens
- Basic reentry mitigation by restricting caller to EOAs (until Pectra hardfork makes tx.origin checks moot)
- Checks tick has not moved too far from last block's tick (approximated in BPS)
- Partial fills up to a max price (approximated in BPS) when liquidity at current tick is low
- Owner-configurable WETH limit per-swap
- Owner-set swap interval period
- Owner-set max deviation from current tick (approximated in BPS)


