# issue: exempt from an eval for the /mockup step

playbook: issue
method-trust: e20ce976dc778d464cfc2b1a6b64531e12eae776495f68ea14a219e583b9689a
exempt: the new /mockup step and the mockup lines in /implement, /e2e and /verify act only on an issue that changes UI or has an approved mockup; the issue eval's fixture is a shell cart with no UI, and its task stops at the /audit-issue decision before step 5, so nothing it does changes
