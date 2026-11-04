package Cx

import data.generic.ansible as ansLib
import data.generic.common as common_lib

modules := {"ansible.builtin.uri", "uri", "ansible.legacy.uri",
            "ansible.builtin.get_url", "get_url", "ansible.legacy.get_url"}

CxPolicy[result] {
	task := ansLib.tasks[id][t]
	mod := task[modules[m]]
	ansLib.isAnsibleFalse(mod.validate_certs)

	result := {
		"documentId": id,
		"resourceType": modules[m],
		"resourceName": task.name,
		"searchKey": sprintf("name={{%s}}.{{%s}}.validate_certs", [task.name, modules[m]]),
		"issueType": "IncorrectValue",
		"keyExpectedValue": "validate_certs should be true",
		"keyActualValue": "validate_certs is false",
		"searchLine": common_lib.build_search_line(["playbooks", t, modules[m], "validate_certs"], []),
	}
}
