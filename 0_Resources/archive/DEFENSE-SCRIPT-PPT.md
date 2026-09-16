# Milestone 2 — Application-Layer Attack Module Implementation

Milestone 2 is about how we actually attack a mesh whose Wi-Fi firmware is closed-source. Since the ESP-WIFI-MESH stack itself is a binary blob, we can't touch raw 802.11 frames - so both attacks are emulated at the application layer using ordinary esp_mesh_send and esp_mesh_recv calls.

The blackhole is one attacker node positioned to receive probe traffic - victims address probes directly to its MAC, which behaviorally stands in for a false short-route advertisement. During baseline and cooldown it forwards normally; the moment the attack phase starts, it silently stops calling esp_mesh_send and packets vanish. The signature is simple: zero forwarded probes reach the root for the whole attack window.

The wormhole needs two attacker nodes - B sits near the victims, A sits near the root, and a physical wired UART link between them is the out-of-band tunnel, which is what makes it a wormhole rather than just forwarding. B captures probe metadata during the attack phase, ships it over UART with a CRC to catch transmission errors, and A reconstructs a replica probe and re-injects it toward root over the legitimate mesh path. So the same logical probe shows up at the root twice - once slow, over the real multi-hop path, and once fast, through the tunnel - with a measurable latency mismatch between the two.

Both signatures show up cleanly in the real logs. I have root-side arrivals.csv captures from all four topologies for both attacks, and they show exactly this: phase transitions logged explicitly - baseline, attack, cooldown, terminate - zero blackhole arrivals during the attack window, and duplicate source-MAC and sequence-number pairs during wormhole runs, always traced back to the tunnel node's MAC. Both attacks toggle cleanly on phase boundaries - no leakage into baseline - and the behavior holds across all four topologies.

# Milestone 3 — Multi-Topology Testbed Deployment

Milestone 3 is proving the mesh actually forms the shape we say it does, in all four topologies from the proposal: star, where every node connects directly to root; tree, a hierarchical structure with intermediate forwarders; linear chain, where nodes are arranged in a line so only adjacent neighbors can reach each other, forcing long multi-hop paths; and partial mesh, where some nodes have more than one potential parent, which is the most realistic case for real deployments.

We don't just claim a topology - we verify it with a script that independently reconstructs the parent-child tree from each node's own parent-MAC and layer columns in its telemetry log. For star it confirms all five nodes sit at layer 2, direct children of root. For linear it confirms one node per layer down to depth six. For tree it confirms multi-hop depth three with intermediate forwarders. For partial mesh it confirms nodes actually switching parents during the run, which is expected - that's what makes it a partial mesh instead of a fixed tree.

I'll be honest about one wrinkle the tool caught: on the tree topology's first blackhole run, the script flagged a warning - two probes still reached the root at over five times the baseline rate, meaning the attacker's silence didn't fully engage that run. That's exactly why tree blackhole is one of the topologies still being repeated - the validation is doing its job, catching a run that needs to be redone rather than letting it slip into the dataset.

Every topology that has completed converges within sixty seconds and holds a fully re-routing-free five-minute baseline, and both attacks show their expected signature in every topology captured so far.

# Milestone 4 — Phase-Controlled Experiment Execution

Milestone 4 is the execution matrix itself. Every run follows the same timeline: one minute for the mesh to form, five minutes of baseline, three minutes with the attack active, two minutes of cooldown. The full matrix is four topologies times two attack types times at least three repeats each, which is a minimum of twenty-four runs. The root broadcasts phase transitions, and every node stamps the current phase ID into its own log rows - that phase ID is the ground-truth label the whole dataset rests on.

Current status: sixteen of twenty-four runs collected. Star and linear are fully done - three repeats each, for both blackhole and wormhole. Tree and partial mesh are the ones still in progress - one repeat done for each attack type on each of those two topologies, two more repeats pending on each. So what's left isn't a new topology or a new attack to design - it's finishing repeats on two already-proven configurations.

Every completed run produces seven files - five child telemetry logs, one root telemetry log, one root arrivals log - and every one of those seven passes checks before it counts toward the twenty-four. I have a live example: a partial-mesh wormhole run showing 901 probes during the attack phase at a rate a quarter above baseline, with 180 of those flagged as duplicate deliveries out of 721 unique probes - one-point-two-five times the expected count - all traced to the tunnel node's MAC. That's the wormhole signature appearing exactly where the pipeline expects it, on a run recorded today.

# Milestone 5 — Raw Data Extraction and Integrity Validation

Milestone 5 is what happens to a run's data the moment it comes off the boards, before anything downstream ever sees it. Each ESP32's CSVs are pulled over USB serial and stored with the run's metadata - topology, attack type, repeat number, collection date. Then a validation script checks three things on every file: sample coverage of at least ninety-five percent of what the configured telemetry rate should have produced, a phase label populated on every single row, and no file corruption or premature truncation.

I can show this running on a real capture - partial mesh, blackhole attack: every one of the seven files passes, with sample coverage between ninety-five and ninety-seven percent across all nodes. The arrivals log breaks the phases down on its own: 1,436 baseline probes at a reference rate of about four per second, zero probes reaching the root during the blackhole phase - flagged explicitly as the expected attack signature - and 481 cooldown probes back at a hundred percent of the baseline rate.

There's a second check worth mentioning: some raw captures actually contain more than one boot session, if a node reset mid-run. The trim tool detects that automatically - one file had four separate sessions logged back to back - and keeps only the longest, real session, dropping the reboot artifacts before the file ever reaches analysis. That's the kind of silent corruption this validation step is built to catch, and it's already caught it. The end result: a validation report confirming clean runs in the final dataset, and any run that fails gets flagged for a repeat instead of quietly going into the dataset broken.
