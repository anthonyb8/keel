# babysit-pr: exempt from an eval for keel merge's skipped checks

playbook: babysit-pr
method-trust: 063be890c09409400c460eadc3470e13b6c4e57b33c15f8bb471036c5ba1f257
exempt: only /merge changed, dropping its question about a skipped check now that keel merge counts a skip as passed; babysit-pr names /merge only to say it never merges, so no babysit-pr session runs the changed text
