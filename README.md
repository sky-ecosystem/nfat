## Assumptions

It is assumed that only simple, regular ERC-20 tokens will be used as `gem`. In particular, the supported tokens are assumed to revert on failure (instead of returning false), not to execute any hook or apply any fee on transfer, and not to execute any rebasing logic.

## Deviations from Laniakea Spec

Below is a non-exhaustive list of deviations from [laniakea-docs](https://github.com/sky-ecosystem/laniakea-docs):

- The spec describes the Redeemer as a separate contract from the Facility. This implementation merges both into a single contract.
- The spec requires `{principal, depositor, mintedAt}` to be stored on-chain for each NFAT. These fields are not used by any contract logic and are therefore omitted from storage.
- The spec describes burning the NFAT on full redemption. This implementation has no on-chain knowledge of deal terms, so NFATs are never burned or spent. Residual payments are tracked off-chain.
- The spec requires complete withdrawal only for the queue. This implementation supports partial withdrawals.
- The spec calls the minting operation `claim`. This implementation uses `issue` to avoid confusion with the redeem-side concept of claiming funded amounts.
- The spec tracks queue deposits through a shares-based accounting system. Since the deposited asset earns no yield while queued, shares would always be 1:1 with the underlying, so this implementation tracks deposits as direct balances instead.
- The spec assumes capital is always claimed from the queue during issuance. This implementation allows `issue` with amount 0, enabling NFAT minting without claiming queued capital for greater flexibility.

## Notes

- The contract inherits OpenZeppelin's ERC721 which advertises support for the ERC721Metadata extension via `supportsInterface`. However, no base URI is configured, so `tokenURI()` returns an empty string for all tokens.
