# babysit-pr: exempt from an eval for the no-mistakes removal

playbook: babysit-pr
method-trust: 9c0fb28d895062b091baadd5a848ea7827c4fbd7efebf2b2c3e2525758f343ff
exempt: step 5 under a contract drops keel gate and keeps /verify; outside a contract the drive mode still stops and asks before each commit and push, so nothing it does unattended changed
