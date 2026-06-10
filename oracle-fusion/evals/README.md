# Oracle Fusion evals

Representative `query → expected_behavior` cases that measure two things:

1. **Discovery** — does the *right* skill load for the query? (Genie selects by
   `description` only, so a miss here is a description bug.)
2. **Quality** — given the skill, is the answer correct (right tables, scope,
   currency basis, balance type, decoded CCID), or — when ambiguous — does it
   surface the right question instead of guessing?

There is no built-in runner; use these in a fresh **Agent-mode** chat and score by
hand, or wire them into your own harness. Each file is one case:

```json
{
  "query": "give me the trial balance for OCT-25",
  "expected_skill": "oracle-fusion-general-ledger",
  "expected_behavior": [
    "Loads oracle-fusion-general-ledger with oracle-fusion-overview as parent",
    "Composes the keystone oracle-fusion-ledger-coa for period + currency + CCID",
    "Uses posted-only journals (STATUS='P') and pins ACTUAL_FLAG='A'"
  ],
  "anti_behavior": [
    "Does NOT sum across ACTUAL_FLAG (actual/budget/encumbrance)",
    "Does NOT order periods alphabetically by PERIOD_NAME"
  ]
}
```

When a case fails on discovery, fix the **description** first. When it fails on
quality, fix in order: UC comment / segment map (via `oracle-fusion-setup`) →
glossary synonym / instruction → certified example query / Trusted Asset /
metric view. Add real misses from the Genie Monitoring tab as new cases over time.

## Case index

| File | Type | Skill under test |
|---|---|---|
| `overview-which-tables.json` | discovery | `oracle-fusion-overview` |
| `setup-glossary.json` | discovery | `oracle-fusion-setup` |
| `ledger-coa-decode-account.json` | discovery + keystone | `oracle-fusion-ledger-coa` |
| `general-ledger-trial-balance.json` | discovery | `oracle-fusion-general-ledger` |
| `procurement-supplier-spend.json` | discovery | `oracle-fusion-procurement` |
| `general-ledger-balance-type-ambiguity.json` | ambiguity | `oracle-fusion-general-ledger` |
| `procurement-spend-basis-ambiguity.json` | ambiguity | `oracle-fusion-procurement` |
| `ledger-coa-which-segment-keystone.json` | keystone | `oracle-fusion-ledger-coa` |
| `genie-agent-curate.json` | discovery | `oracle-fusion-genie-agent` |
| `anti-trigger-non-fusion.json` | anti-trigger | none |
