## Assumptions

It is assumed that only simple, regular ERC-20 tokens will be used as `gem`. In particular, the supported tokens are assumed to revert on failure (instead of returning false), not to execute any hook or apply any fee on transfer, and not to execute any rebasing logic.

## Deviations from Laniakea Spec

Below is a non-exhaustive list of deviations from [laniakea-docs](https://github.com/sky-ecosystem/laniakea-docs):

- The spec describes the Redeemer as a separate contract from the Facility. This implementation merges both into a single contract.
- The spec requires `{principal, depositor, mintedAt}` to be stored on-chain for each NFAT. These fields are not used by any contract logic and are therefore omitted from storage.
- The spec describes burning the NFAT on full redemption. This does not fit well with deals other than single-payment-at-maturity (e.g., loans with periodic interest), as the contract has no knowledge of deal terms and burning would have to be coordinated off-chain with no on-chain purpose. Instead, NFATs are never burned and residual payments are tracked off-chain.
- The spec requires complete withdrawal only for the queue. This implementation supports partial withdrawals.
