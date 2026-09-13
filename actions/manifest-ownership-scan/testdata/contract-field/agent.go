package agent

import agentv0 "example.com/generated/codefly/services/agent/v0"

// A plugin that reads the released Agent.GetEffectiveInputs request field in
// order to DECLINE historical discovery owns neither the type nor any
// repository binding. Declaring such a field is ownership and still fails; see
// the runtime-identifiers fixture.
func targetsCurrentWorktree(req *agentv0.GetEffectiveInputsRequest) bool {
	return req.Revision == ""
}
