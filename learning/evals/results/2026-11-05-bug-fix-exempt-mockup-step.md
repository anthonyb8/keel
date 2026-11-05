# bug-fix: exempt from an eval for the /mockup step

playbook: bug-fix
method-trust: e20ce976dc778d464cfc2b1a6b64531e12eae776495f68ea14a219e583b9689a
exempt: only /e2e and /verify changed, each by a line that applies when the issue has an approved mockup; the bug-fix fixture is a shell cart with no UI or mockup, so nothing it does changes
