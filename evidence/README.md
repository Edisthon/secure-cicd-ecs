# Evidence

After each Jenkins run, download the build's archived artifacts (reports/, sbom/, ecs/rendered/) and
copy them into a run folder here, e.g.:

- `evidence/01-blocked-vulnerable-dependency/`  - failing build (reports + console log + screenshots)
- `evidence/02-passing-after-fix/`              - green build (reports + SBOM + rendered task def)
- `evidence/03-ecs-service-update/`             - ECS console / CLI proof of the new revision running

See `docs/EVIDENCE-CHECKLIST.md` for the exact list.
