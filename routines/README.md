# routines/ — the scheduled remote agent, as code

The version-controlled **source of truth** for the scheduled remote Claude Code agent that
develops this repo. The claude.ai routines backend holds the *running* state; the files
here are the *desired* state. Same pattern as
[`tooming/k8s-anywhere`](https://github.com/tooming/k8s-anywhere/tree/main/routines) and
[`toomingsolutions/easysportstream`](https://github.com/toomingsolutions/easysportstream/tree/main/routines)
— see either repo's own `routines/README.md` for the fuller original writeup.

### Remote scheduled routine (cloud)

**One trigger, one slot/day.** [`routines.yaml`](routines.yaml) is the source of truth —
this section mirrors it, not the other way around. See `routines.yaml`'s comments for the
exact cron and the quota split with the other two repos.

| File | What |
|------|------|
| [`routines.yaml`](routines.yaml) | per-routine metadata: `trigger_id`, `cron`, `model`, env, tools, `prompt_file`, `live_prompt` (the short pointer actually pushed to the live trigger) |
| [`executor.prompt.md`](executor.prompt.md) | **the only live trigger.** Bootstraps `ROADMAP.md` on first run, then implements one item per PR (STEP 8 loop), self-reviews, self-merges |

## Pointer architecture

A live trigger's actual content is `routines.yaml`'s `live_prompt` — a short,
effectively-static instruction telling the run to read `prompt_file` (`executor.prompt.md`)
from the already-checked-out repo and follow it in full. The real operating contract lives
**only** in `prompt_file` and is read fresh every run; it is **never baked into the
trigger**. This means:

- **Editing `executor.prompt.md` needs no apply step at all.** It's a normal PR, reviewed
  like any other diff, live the moment it merges to `main` — the next run reads whatever
  is on `main` at fetch time.
- **Editing `routines.yaml`'s structural fields** (`cron`, `model`, `enabled`,
  `allowed_tools`, `live_prompt`, `environment_id`) is the only thing that still needs the
  apply dance below, because those fields are pushed to the live API.

## Changing the routine

**`executor.prompt.md`**: just edit it and open a PR. Nothing else to do — no apply step,
because it's never baked into the trigger.

**`routines.yaml`** (cadence/model/enabled/tools/`live_prompt`/environment):

1. Edit the file.
2. Open a PR — reviews like any other diff.
3. After merge, **apply**: ask Claude Code *"apply the routines"*. It reads the file and
   syncs the backend — `RemoteTrigger create` when `trigger_id` is empty (then writes the
   new id back here), else `RemoteTrigger update`.
4. Run `make routines-mark-applied` to refresh `.routines-applied`.

## Why "apply" is run by Claude Code, not a CI script

The routines API is reached through Claude Code's in-process `RemoteTrigger` tool with
managed OAuth — there is **no exposed token to `curl`** from CI. So Claude Code is the
"apply" tool, the way someone runs `terraform apply` by hand.

## Why the autonomous executor may not edit routines.yaml

The cloud executor runs with `allowed_tools = [Bash, Read, Write, Edit, Glob, Grep]` — **no
`RemoteTrigger`**. So it physically *cannot* apply a `routines.yaml` change to the live
trigger. If it edited `routines.yaml` and ran `make routines-mark-applied`,
`routines-check` would stay green (the snapshot matches the file) while the **live trigger
silently drifts** from the repo. `scripts/routines-author-check.sh` (`make
routines-author-check`, wired into CI) fails any executor-authored change that touches
`routines.yaml` — "executor-authored" = the branch matches `routines.yaml`'s
`branch_prefix` (`auto/`) *or* the commit author is the cloud identity `Claude
<noreply@anthropic.com>`. If the executor needs a cadence/model/`live_prompt` change, it
opens an issue instead (STEP 6b in `executor.prompt.md`) — a hard tool-access limit, not a
scope choice. It may freely edit `executor.prompt.md` directly, same as any other repo
file.
