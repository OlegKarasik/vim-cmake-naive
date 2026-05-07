# Rules

**Scope:** Global non-negotiable constraints.
**Trigger keywords:** rules, constraints, safety, boundaries, dependencies.
**Depends on:** none.
**Conflicts:** none.
These rules govern AI-agent workflow in this repository and do not define or
constrain plugin runtime functionality.

1. DO NOT create or edit files outside of repository.
2. DO NOT redirect output from commands into files outside of repository.
3. DO NOT add or take dependencies on other plugins.
4. In tests only, any single time-based wait/check interval must not exceed 90 seconds.
5. These global core rules override conflicting local core rules for AI-agent workflow.
6. Global asynchronous rules in `global-async-rules.txt` (umbrella root) are mandatory and override conflicting local async rules.
