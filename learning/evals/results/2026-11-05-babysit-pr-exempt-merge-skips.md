# babysit-pr: exempt from an eval for the /merge skip rule

playbook: babysit-pr
method-trust: 5ae4aa4a6a8abe6b5d35839532835d767cceb77e6d0a5417d186e099243d6064
exempt: only /merge changed, in how it treats a skipped check; babysit-pr names /merge only to say it never merges, so no babysit-pr session runs the changed text
