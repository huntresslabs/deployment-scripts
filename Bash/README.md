## Installing the Huntress macOS Agent

This script is meant to be a generic script for deploying the Huntress macOS agent with any tool that supports bash (or shell) scripting.

### Required Values

On lines 44 and 48 you will see two variables (`defaultAccountKey` and `defaultOrgKey`) that need to be updated. The [Account Key](https://support.huntress.io/hc/en-us/articles/4404012734227#account-key) is located in your Huntress Portal. This value is used to associate the agent with your tenant. The [Organization Key](https://support.huntress.io/hc/en-us/articles/4404012734227#organization-keys) is used to organizations agents by customer within your portal. You can replace the provided `"Mac Agents"` value in the script with your customer name whem you run the script (spaces are permitted if you keep the name in double quotes), or you may simply [move the agents](https://support.huntress.io/hc/en-us/articles/4404012577299-Moving-Agents-Between-Organizations) to the appropriate organization after installation. 

### Optional Values

On line 52 you'll notice a value for `RMM`. This optional value allows  you to name the tool you're using to install the Huntress macOS agent, which may be helpful for our support team when troubleshooting. The value there is written to the `/tmp/HuntressInstaller.log` log file during installation and is not automatically sent to Huntress.

On line 58, there is an option called `install_system_extension`. If set to `true`, the script will attempt to install the system extension after the Huntress Agent is installed. This will only succeed if the endpoint is [properly configured with MDM permissions](https://support.huntress.io/hc/en-us/articles/21286543756947-Instructions-for-the-MDM-Configuration-for-macOS) for the system extension. If the endpoint does not have these permissions in place beforehand, then the currently logged in user will receive security prompt pop-ups asking to authorize the system extension and content filter. Examples of this can be found in [this KB article](https://support.huntress.io/hc/en-us/articles/21286469262867-Install-the-System-Extension-for-macOS)

**NOTE**: Please do not modify anything below line 58.

### Running from command line with arguments

Some tools don't have a scripting engine, but will permit you to upload a script and pass parameters to it. If you need to run this as a script with parameters, simply follow the guidelines below:

```
-a, --account_key      <account_key>      The account key to use for this agent install
-o, --organization_key <organization_key> The org key to use for this agent install
```

As noted above, there are two required fields that can be defined statically in the script, or you can pass the values as parameters. The `organization_key` parameter supports strings, so if you pass `My Company`, just be sure to put it in double quotes like so: `"My Company"`

Example usage:

`./InstallHuntress-macOS-bash.sh --account_key 123456abcdef --organization_key "My Awesome Coffee Shop"`

### Logging and Troubleshooting

The installer log is located in `/tmp/HuntressInstaller.log` and the output of a successful install would look like:

```
20221103-085511 -- =========== INSTALL START AT 20221103-085511 ===============
20221103-085511 -- =========== Syncro macOS deployment component | Version: 1.0 ===============
20221103-085511 -- --organization_key parameter present, set to: My Awesome Coffee Shop
20221103-085511 -- Provided Huntress key: 1234************************cdef
20221103-085511 -- Provided Organization Key: My Awesome Coffee Shop
20221103-085511 -- =============== Begin Installer Logs ===============
20221103-085511 -- creating /tmp/hagent.yaml...
running the installer...
installer: Package name is Huntress Agent
installer: Upgrading at base path /
installer: The upgrade was successful.
cleaning up...
20221103-085511 -- =========== INSTALL FINISHED AT 20221103-085511 ===============
```

## Huntress PPPC
The `Huntress PPPC.mobileconfig` is designed to upload/import to your MDM and can then be scoped to a collection of devices. This payload will grant the Huntress agent FDA (full disk access) and allow for the optimal performance of the Huntress agent.

Further details: [Generic Deployment and PPPC Payload for Full Disk Access](https://support.huntress.io/hc/en-us/articles/10962515436691)

