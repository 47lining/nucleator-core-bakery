Nucleator AMI Bakery
====================

A Nucleator stackset that bakes required AMIs.

Commands:

provision
	Inputs:
	- customer
	- cage (defaults to 'build')
	- source AMI (optional, by id or tag name/value.  uses reference ami in {{group}}_stackset if not specified.)
	- group determines an Ansible provisioning playbook/role
	Output:
	- CF stack with initial instance, ready for ansble comms.

configure:
	- apply configuration for specified group to instance launched via provision

publish:
	- create AMI from EC2 instance in specified bakery stackset instance

delete:
	- delete specified bakery stackset instance
