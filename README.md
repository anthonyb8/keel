# keel

The setup every Claude session runs in: enforced rails, one front door that picks a playbook for the task, and a trust layer that lets an agent be left alone with a task and trusted with what it brings back.

keel is built beside [harness](https://github.com/anthonyb8/harness) and replaces it once it reaches parity.
Until then it never writes a harness path: a keel session runs through `keel claude`, on its own config dir, and a plain `claude` stays exactly as it was.

## Install

```sh
git clone git@github.com:anthonyb8/keel.git ~/keel
~/keel/install.sh            # link keel's files into ~/.keel/claude and ~/.local/bin/keel
~/keel/install.sh --check    # report drift without changing anything
keel claude                  # then /login once in this session
```

Requires `claude`, `jq` and `git`.

`keel claude` runs `claude` with `CLAUDE_CONFIG_DIR=~/.keel/claude`.
Its login, transcripts, memory, plugins and background jobs live there, apart from harness's.
The variable is set by `keel claude` alone, never in the shell or a settings file.

## The four layers

- **Rails** keep a session inside the lines whatever it decides: permission lists, trees, gates and git-guard.
- **Method** picks how a task is done: one front door that routes to a playbook, and the skills those playbooks run.
- **Trust** lets a run be left alone: a contract, a done check, a decision log and an independent verifier.
- **Learning** turns what a session taught into edits to the rules, held to a blind eval.

`rules/` holds the rules every session loads, beneath all four.

## Layout

Each directory is created by the row that first puts something in it.

```
rules/       CLAUDE.md, OPINIONS.md, VOICE.md
rails/       bin/keel, settings.json; later git-guard, hooks and shell
method/      the mode, playbooks, skills and agents
trust/       the contract, its hooks and skills
learning/    reflect and evals
templates/   issue and project templates
docs/        how each part works
tests/       run.sh for the logic, against a throwaway HOME
```

## Tests

```sh
tests/run.sh    # install and keel claude under a throwaway HOME; touches nothing on the machine
```

CI runs shellcheck and `tests/run.sh` on every pull request.
