# babysit-pr: exempt from an eval for the /mockup step

playbook: babysit-pr
method-trust: e20ce976dc778d464cfc2b1a6b64531e12eae776495f68ea14a219e583b9689a
exempt: only /verify changed, by one brief line that applies when the issue has an approved mockup; the babysit-pr fixture is a shell cart with no UI or mockup, so nothing it does changes
