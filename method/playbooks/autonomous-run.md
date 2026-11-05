# autonomous-run

Do a task unattended under a contract the user approved, ending with a draft PR the verifier and the gate have passed.

## Steps

1. Draft the contract from the user's prompt with `~/.keel/trust/contract.md`, then stop for their approval; this is the run's only stop **(stop)**.
2. Start the run in a fresh tree with the approved contract: `EnterWorktree`, then `keel run start --contract <file>`.
3. Loop: make the smallest justified change, check it, commit it if granted, and log a decision row; when the check stops improving, change approach rather than stop, and never loosen the done check to declare victory.
4. Once the done check passes, run `/verify`, fixing and re-verifying until it passes.
5. Run `keel gate`, then bring back and fold its fixes, and `/verify` again if the tree changed.
6. Push and open a draft PR as granted, with the body from the project's PR template and the run's Attention items under its notes.
7. Stop the run as done with `keel run stop done`, and reply with `/catchup`'s summary.

## Reply

`/catchup`'s summary: Attention first, then the steps, the done check, the verifier's and the gate's verdicts, and the draft PR's URL.
