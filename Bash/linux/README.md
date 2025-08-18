## Installing the Huntress Linux Agent

This script is meant to be used for installing the Huntress Linux agent with any tool that supports bash (or shell) scripting.

### Running from the command line with arguments

Running the script without any arguments will display the usage text for the script:

```
[Huntress Logo]

Usage: ./huntress-linux-install.sh [options...] --account_key <account_key> --organization_key <organization_key>

-a, --account_key      <account_key>      The account key to use for this agent install
-o, --organization_key <organization_key> The org key to use for this agent install
-t, --tags             <tags>             A comma-separated list of agent tags
-v, --verbose                             Print info during install
    --batch_only                          Do not prompt the user for missing info
-h, --help                                Print this message
```

### Required Values

The [Account Key](https://support.huntress.io/hc/en-us/articles/4404012734227#account-key) is located in your Huntress Portal. This value is used to associate the agent with your tenant.
The [Organization Key](https://support.huntress.io/hc/en-us/articles/4404012734227#organization-keys) is used to organize agents by customer within your portal. Provide an organization key you wish your agent to appear under when you run the script. If the organization does not exist, it will be created automatically. If you need to change which organization your agent appears in after installation, you may simply [move the agents](https://support.huntress.io/hc/en-us/articles/4404012577299-Moving-Agents-Between-Organizations) to the appropriate organization.

Some tools don't have a scripting engine, but will permit you to upload a script and pass parameters to it. If you need to run this as a script with parameters, simply follow the guidelines below:

```
-a, --account_key      <account_key>      The account key to use for this agent install
-o, --organization_key <organization_key> The org key to use for this agent install
```

The `organization_key` parameter supports strings, so if you pass `My Company`, just be sure to put it in double quotes like so: `"My Company"`

Example usage:

`sudo ./huntress-linux-bash.sh --account_key 0123456789 --organization_key "My Company"`

### Optional Values

You may also provide the following parameters:

```
-t, --tags             <tags>             A comma-separated list of agent tags
-v, --verbose                             Print info during install
    --batch_only                          Do not prompt the user for missing info
-h, --help                                Print this message
```

### Troubleshooting

Ensure that the script is ran with elevated permissions (ex. sudo).

Ensure that the script is executable for the owner.

The installer will echo the script status to the terminal and the output of a successful install would look like:

```
2025-06-10T19:56:59  ---- Installing Huntress EDR for Linux | script version: 0.0.1 ----
2025-06-10T19:56:59 [+] Downloading latest package
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 7252k  100 7252k    0     0  3729k      0  0:00:01  0:00:01 --:--:-- 9394k
2025-06-10T19:57:01 [+] Unpacking installer
2025-06-10T19:57:01 [+] Configured agent with given settings
2025-06-10T19:57:01 [+] Installing Huntress Services
2025-06-10T19:57:02 [+] Starting Huntress Services
2025-06-10T19:57:02  ---- Finished Installing Huntress EDR for Linux | script version: 0.0.1 ----
```
