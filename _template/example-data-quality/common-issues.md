# Common <Source> Data-Quality Issues

Symptom → most-likely cause matrix. Walk the diagnostic playbook in SKILL.md first; consult this file when the symptom doesn't match an obvious probe.

| Symptom | Most-likely cause | Probe |
|---|---|---|
| Backlog count higher than source UI | Missing `WOCLASS = 'WORKORDER'` filter or double-counting `ISTASK = 1` | 4, 5 |
| Backlog count lower than source UI | Closure table stale; ingestion lag; `STATUS IN (open set)` mismatch | 6, 1 |
| Status history is sparse / missing | REST-API ingestion path (`WORKORDER` PATCH'd but `WOSTATUS` not written) | 2 |
| Same WO appears multiple times in result | `JOIN` missing `SITEID` (multi-site cross-product) | 3 |
| "By region" rollups give wrong totals | Closure table stale or recursive depth cap exceeded | 6 |
| Genie keeps generating wrong SQL despite correct schema | UC comments out of date or missing | 7 |
