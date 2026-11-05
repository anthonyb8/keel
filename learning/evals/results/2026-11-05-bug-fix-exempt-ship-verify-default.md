# bug-fix: exempt from an eval for verifying by default on /ship

playbook: bug-fix
method-trust: 2f589371db6fb866eb988d0a95052cc1eb3e68182d6a8c7668f9641b9f732824
exempt: only /ship and /verify changed, and the bug-fix playbook stops before /ship outside a contract, so its eval task never reaches either; under a contract the run verifies as before, which the autonomous-run eval covers
