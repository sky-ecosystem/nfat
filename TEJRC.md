# TEJRC

Tokenized External Junior Risk Capital lets a Prime raise junior risk capital from external
providers through an NFAT facility.

A provider commits capital and receives an NFAT. Its principal is destroyed at issuance, paying
down the Prime's debt, so the provider never holds a claim against the Prime. Its claim is on a
payout that Sky mints up front and that sits in escrow for the term, reducible only by an
attested loss. At term anyone can release the escrow into the facility, and the holder collects.

Reference figures throughout: **20m** committed, **22m** redemption, one year term, attested
loss `L`.

## Contracts

| | |
| --- | --- |
| `NFATFacility` | Used unchanged. Holds the provider's subscription until issuance, and the payout from release until collection |
| `TEJRCEscrow` | One per facility. Holds each NFAT's payout until its term elapses |

The TEJRC facet in the PAU repo drives both from the Prime's proxy.

## Flow

| # | Action | Who | Call |
| --- | --- | --- | --- |
| 1 | Mint 22m, then deposit it to the escrow against the intended token id | operator, optionally one multisig batch | `USDSFacet.mint`, then `TEJRCFacet.deposit` |
| 2 | Subscribe 20m, with the agreed conditions as `data` | **the provider, directly** | `NFATFacility.subscribe` |
| 3 | Issue the NFAT and burn the provider's 20m | operator, one call | `TEJRCFacet.issue` |
| 4 | Apply an attested loss: withdraw `L` from the escrow | operator / attester | `TEJRCFacet.withdraw`, or `TEJRCEscrow.withdraw` direct from a bud |
| 5 | Release the escrow into the facility | **anyone**, once past the term end | `TEJRCEscrow.repay` |
| 6 | Collect | **the provider, directly** | `NFATFacility.collect` |

Step 3 is a single transaction, so the provider's principal is never left sitting in the proxy.
Step 1 need not be — the payout simply has to be in escrow before step 3 — but batching it keeps
the mint from resting in the proxy either.

The `L` withdrawn at step 4 returns to the proxy and is burned there whenever convenient. It does
not have to happen in the same transaction, or soon after.

Step 3 checks `balances[tokenId] >= principal` on the escrow before issuing. A token id with no
payout behind it cannot be issued, which makes the ordering structural rather than procedural,
and turns a mismatch between the anticipated and the actual id into a revert rather than an
unfunded NFAT.

Step 5 releases whatever the escrow still holds. Because losses are applied by withdrawing
before term, the remaining balance is already the correct figure — the release needs no price,
no attestation and no governance input, and the caller has no say in the amount.

## `TEJRCEscrow`

Constructed against one facility, with the `gem` read from it — both immutable. `facility()` is
exposed so the facet can verify the pairing when it is configured. The proxy it pairs with is
filed by governance after deployment, so until that is set the contract is inert.

**`deposit(tokenId, amount, termEnd)`** — **`almProxy` only**, not a role. Funds are pulled
from the caller, so they could only come from the proxy anyway; requiring it makes that
structural. Records `amount` against the token id. The first deposit fixes the term end; later
deposits must pass the same one, so a payout already committed can never be delayed. **Every**
deposit must be at least `minTerm` short of that end, not just the first — otherwise a late
deposit could attach to a term end about to elapse and be released without ever having been
immobile.

The effect is that funds cannot be added within `minTerm` of the end. If a payout is ever short
at that point, `NFATFacility.repay` is permissionless, so the shortfall can be paid into the
facility directly without going through the escrow.

**`withdraw(tokenId, amount)`** — operator. Returns funds to `almProxy`. This is how an
attested loss is applied: withdraw the haircut before term, leaving exactly what the holder is
owed. Funds can only ever go to `almProxy`, so this contract cannot be a route to move value
elsewhere — it returns them to the proxy, where the ordinary rate limits apply. Only governance
can repoint it.

A withdrawal that empties the balance also clears the term end, so the id can be redeposited
against a fresh one. That is the only way to correct a term end set in error. A partial
withdrawal keeps it, so applying a haircut can never move a committed payout.

**`repay(tokenId)`** — **permissionless**, once past the term end. Releases the entire balance
into the facility. Takes no amount.

## Configuration

| | |
| --- | --- |
| `almProxy` | the paired proxy — the only permitted depositor, and the only destination for withdrawals |
| `minTerm` | how far ahead a first deposit must set its term end |
| `buds` | may withdraw, and nothing else — see below |
| `wards` | governance |

`facility` is a constructor argument and immutable. `almProxy` is filed, so a proxy migration
does not strand the escrow — but it also means governance can repoint both the deposit gate and
the withdrawal destination.

Since `deposit` is gated on the proxy address rather than a role, **`withdraw` is the only
role-gated function here, so `buds` means exactly "may withdraw"**. A bud can call the escrow
directly, without going through the Controller or holding `ALLOCATOR_ROLE`, so this is a way to
grant a narrow permission rather than a broad one. Candidates are the paired proxy, whoever
applies attested losses, and governance if it ever needs to recover funds.

A rogue bud can only push funds back to `almProxy`, so the exposure is unwanted haircuts and
delayed payouts, not theft.

`minTerm` is why this contract needs no rate limits of its own, and it is the guard the design
actually rests on. Depositing does not move value out of the system — the escrow can only return
funds to the proxy or pay the paired facility — so what needs bounding is not the amount but how
long a mistake stays uncorrectable. A deposit made in error is reversible for at least `minTerm`,
which is the window in which the facility can be stopped, the operator removed and the deposit
withdrawn.

The facet still rate limits its deposit leg, since every other leg that moves funds out of the
proxy has one and there is no reason to be the exception. But it is belt and braces rather than
the load-bearing control, and can be set generously.

That window is detection-dependent. Monitoring every `Deposit` against the expected redemption
for that token id is part of the design, not an optional extra.

No freezer is needed on the escrow. `NFATFacility.repay` is gated on `stopped`, so stopping the
facility already halts every release.

## The TEJRC facet

Lives in the PAU repo, not here. It is where the rate limits and the operator role checks sit.
Specified here only because it is half of the mechanism; TODO: consider moving this section to
the PAU repo once the facet is written there.

**`setEscrow(facility, escrow)`** — governance. Records which escrow pairs with which facility.
Should verify `escrow.facility() == facility` at this point, so a misconfiguration fails once, at
governance time, rather than on every later call.

**`deposit(facility, tokenId, amount, termEnd)`** — allocator. Approves the escrow for `amount`,
calls through the proxy, resets the approval. Rate limited, in line with every other leg that
moves funds out of the proxy — though `minTerm` on the escrow is the guard that actually matters
here, which is what makes it safe to raise this limit over time as volume grows.

**`issue(facility, to, tokenId, amount)`** — allocator. Requires the facility's gem to be USDS,
since the burn is a buffer transfer plus a vault `wipe`. The escrow itself is gem-agnostic, so
that constraint is the facet's, not the design's. One call that:

1. requires `escrow.balances(tokenId) >= amount`, so a token id with no payout behind it cannot
   be issued and an id that does not match the deposit reverts rather than going unfunded;
2. issues the NFAT through the facility, which moves the provider's principal into the proxy;
3. measures what actually arrived, and burns exactly that.

Steps 2 and 3 being one transaction is what keeps the provider's principal from resting in the
proxy.

**`withdraw(facility, tokenId, amount)`** — allocator. Returns funds from the escrow to the
proxy. Rate limited like the other inbound legs, where the key doubles as an enable switch —
an unset one disables the path. Note it only bounds the proxy path: a bud can call the escrow
directly, so this is not a bound on withdrawals generally.

### Rate limits

| | Keyed on | |
| --- | --- | --- |
| `LIMIT_TEJRC_ISSUE` | `(facility, provider)` | also the provider whitelist — an address with no key set cannot receive |
| `LIMIT_TEJRC_DEPOSIT` | `(facility, gem)` | belt and braces; `minTerm` is the real bound, so this can be set generously |
| `LIMIT_TEJRC_WITHDRAW` | `(facility)` | for consistency with other inbound legs; only binds the proxy path |

The burn in `issue` is not metered separately — there is no shared budget with `USDSFacet`, so
the total burned across both is not bounded anywhere. `LIMIT_TEJRC_ISSUE` is the bound on this
leg: what gets burned is what the issuance brought in.

### What it deliberately does not have

**No `repay`.** The escrow calls the facility itself, permissionlessly. A facet function would
mean a permissionless path into `ALMProxy.doCall`, which the proxy's custody model rules out.

**No per-position accounting.** No outstanding principal, no accruing ceiling, no funded counter.
The escrow balance is the record, which is why the release needs no figure from anywhere.

### Wiring

Governance must not set `LIMIT_NFAT_HALO_ISSUE` for a facility used for TEJRC, on any Controller
whose proxy is an operator on it. `NFATHaloFacet.issue` reaches the same facility and bypasses
both the escrow check and the atomic burn, leaving an NFAT with no payout behind it.

## What this does not cover

- **The facility's admin surface.** `wards` there can still divert a funded payout through
  `rescueCollectable`, and a freezer can temporarily block collection until governance calls
  `start`.
- **Who may hold an NFAT.** Eligibility lives in the facility's identity network and in the
  issue rate limit, not here.
- **Retiring a spent NFAT.** The facility has no burn path, so collected positions persist at
  zero.
