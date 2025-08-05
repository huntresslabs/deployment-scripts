# Ansible

## Setup

1. Create an Ansible inventory for your hosts. `inventory.yaml` is an example that can be used as a starting point. If you already have inventory files, add your `account_key` as a global or top level variable, and set `organization_key` variables as you see fit. Both variables are required for each host.
2. Optionally, tags can be set at the global, organization, or host level.

## Installation

```sh
ansible-playbook -i inventory.yaml install_huntress.yaml
```

## Uninstall

```sh
ansible-playbook -i inventory.yaml remove_huntress.yaml
```
