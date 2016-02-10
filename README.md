Nucleator AMI Bakery
====================

A Nucleator stackset that bakes AMIs.

Commands:

provision (Create/configure a test instance)
	- customer: name of customer from nucleator config
	- cage: name of cage from nucleator config (default: build)
	- ami-id: source AMI (optional, by id or tag name/value.  uses reference ami in {{group}}_stackset if not specified.)
	- ami-name
	The specified ami must reside in the same AWS Region as the specified Nucleator cage.
	- group: determines an Ansible provisioning playbook/role
	- name: The name to apply to the resulting bakery Stackset instance (default: singleton)

configure (apply configuration for specified group to instance launched via provision)
	- customer: name of customer from nucleator config
	- cage: name of cage from nucleator config (default: build)
	- name: The name to apply to the resulting bakery Stackset instance (default: singleton)
	- group: determines an Ansible provisioning playbook/role

publish (create AMI from EC2 instance in specified bakery stackset instance)
	- customer: name of customer from nucleator config
	- cage: name of cage from nucleator config (default: build)
	- name: The name to apply to the resulting bakery Stackset instance (default: singleton)
	- group: determines an Ansible provisioning playbook/role
	- ami-region: Name of region (default is the region in which the cage lives)
	- ami-name: The Name tag to give the created AMI

delete (delete specified bakery stackset instance)
	- customer: name of customer from nucleator config
	- cage: name of cage from nucleator config (default: build)
	- name: The name to apply to the resulting bakery Stackset instance (default: singleton)
	- group: determines an Ansible provisioning playbook/role
