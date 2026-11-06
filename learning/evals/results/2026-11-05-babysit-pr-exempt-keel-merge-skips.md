# babysit-pr: exempt from an eval for keel merge's skipped checks

playbook: babysit-pr
method-trust: 6aa93a93d1d7cd685ac0b2ce2a3727620da214a4871ce1ee11ff5bf29303d122
exempt: only /merge changed, in how it describes a skipped check keel merge could not explain; babysit-pr names /merge only to say it never merges, so no babysit-pr session runs the changed text
