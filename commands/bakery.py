
from nucleator.cli.utils import ValidateCustomerAction
from nucleator.cli.command import Command
from nucleator.cli import properties
from nucleator.cli import ansible

import os, subprocess, re, hashlib

class StacksetCommand(Command):

    name = "bakery"
    service_role_name = "NucleatorBakeryServiceRunner"
    im_role_name = "NucleatorBakeryInventoryManager"

    def parser_init(self, subparsers):
        """
        Initialize parsers for this command.
        """
        # add parser for builder command
        command_parser = subparsers.add_parser(self.name)
        command_subparsers=command_parser.add_subparsers(dest="subcommand")

        #
        # provision subcommand
        #
        command_provision=command_subparsers.add_parser('provision', help="Create/configure a test instance")
        command_provision.add_argument("--customer", required=True, action=ValidateCustomerAction, help="Name of customer from nucleator config")
        command_provision.add_argument("--cage", required=False, default="build", help="Name of cage from nucleator config (default: build)")
        command_provision.add_argument("--ami-id", required=False, help="Use the ami with this id instead of that specified by the Nucleator Group role.  The specified ami must reside in the same AWS Region as the specified Nucleator cage.")
        command_provision.add_argument("--ami-name", required=False, help="Use the ami with this name instead of that specified by the Nucleator Group role.  The specified ami must reside in the same AWS Region as the specified Nucleator cage.")
        command_provision.add_argument("--name", required=False, default="singleton", help="The name to apply to the resulting bakery Stackset instance")
        command_provision.add_argument("--group", required=True, help="The Nucleator Group, i.e. type of instance, that to provision for baking.")

        #
        # configure subcommand
        #
        command_configure=command_subparsers.add_parser('configure', help="[re]configure a provisioned nucleator bakery stackset")
        command_configure.add_argument("--customer", required=True, action=ValidateCustomerAction, help="Name of customer from nucleator config")
        command_configure.add_argument("--cage", required=False, default="build", help="Name of cage from nucleator config (default: build)")
        command_configure.add_argument("--name", required=False, default="singleton", help="The name of the bakery Stackset instance to configure")
        command_configure.add_argument("--group", required=True, help="The Nucleator Group, i.e. type of instance, to bake within specified Stackset instance.")

        # potentially useful for baking ad-hoc instances outside of a bakery Stackset?
        # command_configure.add_argument("--instance-id", required=False, help="The ID of the running instance to configure")
        # command_configure.add_argument("--instance-name", required=False, help="The name of the instance to configure")

        #
        # publish subcommand
        #
        command_publish=command_subparsers.add_parser('publish', help="create ami for specified group in specified nucleator bakery stackset instance")
        command_publish.add_argument("--customer", required=True, action=ValidateCustomerAction, help="Name of customer from nucleator config")
        command_publish.add_argument("--cage", required=False, default="build", help="Name of cage from nucleator config")
        command_publish.add_argument("--name", required=False, default="singleton", help="The name of the bakery Stackset instance containing the ec2 instance to publish")
        command_publish.add_argument("--group", required=True, help="The Nucleator Group to publish")
        # TODO accept multiple regions, publish AMI to each one.
        command_publish.add_argument("--ami-region", required=False, help="Name of region (default is the region in which the cage lives")
        command_publish.add_argument("--ami-name", required=True, help="The Name tag to give the created AMI")
        # TODO accept additional Tag key/value pairs to apply to resulting AMIs

        # potentially useful for baking ad-hoc instances outside of a bakery Stackset?
        command_publish.add_argument("--instance-id", required=False, help="The ID of the running instance to configure")
        command_publish.add_argument("--instance-name", required=False, help="The name of the instance to configure")

        #
        # delete subcommand
        #
        command_delete=command_subparsers.add_parser('delete', help="delete specified nucleator bakery stackset")
        command_delete.add_argument("--customer", required=True, action=ValidateCustomerAction, help="Name of customer from nucleator config")
        command_delete.add_argument("--cage", required=True, help="Name of cage from nucleator config")
        command_delete.add_argument("--name", required=True, help="The name of the bakery Stackset instance containing the ec2 instance to delete")
        command_delete.add_argument("--group", required=True, help="The Nucleator Group, i.e. type of instance, to bake within specified Stackset instance.")


    def provision(self, **kwargs):
        """
        This command provisions instances that provide the foundation for required AMIs.
        """
        cli = Command.get_cli(kwargs)

        customer = kwargs.get("customer", None)
        if customer is None:
            raise ValueError("customer must be specified")

        cage = kwargs.get("cage", None)
        if cage is None:
            raise ValueError("Internal Error: cage should be specified but is not")

        ami_id = kwargs.get("ami_id", "None")
        ami_name = kwargs.get("ami_name", "None")

        stackset_instance_name = kwargs.get("name", None)
        if stackset_instance_name is None:
             raise ValueError("Internal Eror: name should be specified but is not")

        bakery_group = kwargs.get("group", None)
        if customer is None:
            raise ValueError("group must be specified")

        extra_vars={
            "cage_name": cage,
            "customer_name": customer,
            "ami_id": ami_id,
            "ami_name": ami_name,
            "bakery_group": bakery_group,
            "verbosity": kwargs.get("verbosity", None),
        }

        extra_vars["service_name"] = bakery_group

        namespaced_service_name="{0}-{1}-{2}-{3}".format(self.name, stackset_instance_name, cage, customer)
        namespaced_service_name = self.safe_hashed_name(namespaced_service_name, 100)
        extra_vars["cli_stackset_name"] = self.name
        extra_vars["cli_stackset_instance_name"] = namespaced_service_name

        command_list = []
        command_list.append("account")
        command_list.append("cage")
        command_list.append(self.name)

        inventory_manager_rolename = self.im_role_name

        playbook = "%s_provision.yml" % self.name

        cli.obtain_credentials(commands = command_list, cage=cage, customer=customer, verbosity=kwargs.get("verbosity", None))

        rc = cli.safe_playbook(self.get_command_playbook(playbook),
                                 inventory_manager_rolename,
                                 is_static=True, # dynamic inventory not required
                                 **extra_vars
        )
        # It would be nice at some point to run a configure on what we just provisioned
        # result=dict(stdout=playbook_out, stderr=playbook_err, rc=rc, fatal=FOUND_FATAL)
        #  {'fatal': False, 'rc': 0, 'stderr': '', 'stdout': '\nPLAY [....'}
        # if rc.rc != 0:
        #   return rc
        # get instance id back from playbook
        # parse from rc.stdout?
        # extra_vars["instance_id"] = ""
        # playbook = "%s_configure.yml" % self.name
        # rc = cli.safe_playbook(self.get_command_playbook(playbook),
        #                          inventory_manager_rolename,
        #                          is_static=True, # dynamic inventory not required
        #                          **extra_vars
        # )
        return rc

    def safe_hashed_name(self, value, max):
        length = len(value)
        if length < max:
            return value
        trunc = value[:max - 6]
        hashed = hashlib.md5(value).hexdigest()
        return trunc + hashed[:6]

    def validate_names(self, bsname, envname):
        alphanum = re.compile("^[a-zA-Z0-9-]*$")
        if len(bsname) > 99 or bsname.find('/') > -1:
            raise ValueError("Invalid namespaced application name {0} (must be < 100 characters and not contain a / character)".format(bsname))
        if alphanum.match(bsname) is None:
            raise ValueError("Invalid namespaced application name {0} (must contain only alphanumeric characters and dashes)".format(bsname))
        if len(envname) < 4 or len(envname) > 23 or envname.find('/') > -1:
            raise ValueError("Invalid namespaced beanstalk environment name {0} (must be < 23 characters and not contain a / character)".format(envname))
        if alphanum.match(envname) is None:
            raise ValueError("Invalid namespaced environment name {0} (must contain only alphanumeric characters and dashes)".format(envname))

    def configure(self, **kwargs):
        """
        This command configures an instance of a given node_type
        """
        cli = Command.get_cli(kwargs)

        customer = kwargs.get("customer", None)
        if customer is None:
            raise ValueError("customer must be specified")

        cage = kwargs.get("cage", None)
        if cage is None:
            raise ValueError("Internal Error: cage should be specified but is not")

        stackset_instance_name = kwargs.get("name", None)
        if stackset_instance_name is None:
             raise ValueError("Internal Eror: name should be specified but is not")

        bakery_group = kwargs.get("group", None)
        if customer is None:
            raise ValueError("group must be specified")

        extra_vars={
            "cage_name": cage,
            "customer_name": customer,
            "bakery_group": bakery_group,
            "verbosity": kwargs.get("verbosity", None),
        }

        extra_vars["service_name"] = bakery_group

        namespaced_service_name="{0}-{1}-{2}-{3}".format(self.name, stackset_instance_name, cage, customer)
        namespaced_service_name = self.safe_hashed_name(namespaced_service_name, 100)
        extra_vars["cli_stackset_name"] = self.name
        extra_vars["cli_stackset_instance_name"] = namespaced_service_name

        command_list = []
        command_list.append(self.name)

        inventory_manager_rolename = self.im_role_name

        playbook = "%s_configure.yml" % self.name

        cli.obtain_credentials(commands = command_list, cage=cage, customer=customer, verbosity=kwargs.get("verbosity", None)) # pushes credentials into environment

        return cli.safe_playbook(
            self.get_command_playbook(playbook),
            inventory_manager_rolename,
            **extra_vars
        )

    def publish(self, **kwargs):
        """
        This command publishes the instance to an AMI
        """
        cli = Command.get_cli(kwargs)

        customer = kwargs.get("customer", None)
        if customer is None:
            raise ValueError("customer must be specified")

        cage = kwargs.get("cage", None)
        if cage is None:
            raise ValueError("Internal Error: cage should be specified but is not")

        stackset_instance_name = kwargs.get("name", None)
        if stackset_instance_name is None:
             raise ValueError("Internal Eror: name should be specified but is not")

        bakery_group = kwargs.get("group", None)
        if customer is None:
            raise ValueError("group must be specified")

        ami_name = kwargs.get("ami_name", None)
        if ami_name is None:
            raise ValueError("An ami name must be specified")

        ami_region = kwargs.get("ami_region", None)

        extra_vars={
            "cage_name": cage,
            "customer_name": customer,
            "bakery_group": bakery_group,
            "ami_name": ami_name,
            "ami_region": ami_region,
            "verbosity": kwargs.get("verbosity", None),
        }

        extra_vars["service_name"] = bakery_group

        namespaced_service_name="{0}-{1}-{2}-{3}".format(self.name, stackset_instance_name, cage, customer)
        namespaced_service_name = self.safe_hashed_name(namespaced_service_name, 100)
        extra_vars["cli_stackset_name"] = self.name
        extra_vars["cli_stackset_instance_name"] = namespaced_service_name

        command_list = []
        command_list.append(self.name)

        inventory_manager_rolename = "NucleatorBakeryPublisher"

        playbook = "%s_publish.yml" % self.name

        cli.obtain_credentials(commands = command_list, cage=cage, customer=customer, verbosity=kwargs.get("verbosity", None)) # pushes credentials into environment

        return cli.safe_playbook(
            self.get_command_playbook(playbook),
            inventory_manager_rolename,
            **extra_vars
        )

    def delete(self, **kwargs):
        """
        This command deletes a bakery stackset
        """
        kwargs["bakery_deleting"]=True
        return self.provision(**kwargs)

# Create the singleton for auto-discovery
command = StacksetCommand()
