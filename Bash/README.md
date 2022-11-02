### Installing the Huntress macOS Agent

This script is meant to be a generic tool for deploying the Huntress macOS agent with any tool that supports bash (or shell) scripting.

### Required Values

On lines 44 and 48 you will see `defaultAccountKey` and `defaultOrgKey` that need to be updated. The [Account Key](https://support.huntress.io/hc/en-us/articles/4404012734227#account-key) is located in your Huntress Portal. This value is used to associate the agent with your tenant. The [Organization Key](https://support.huntress.io/hc/en-us/articles/4404012734227#organization-keys) is used to organizations agents by customer within your portal. You can replace the provided `"Mac Agents"` value in the script with your customer name whem you run the script (spaces are permitted if you keep the name in double quotes), or you may simply [move the agents](https://support.huntress.io/hc/en-us/articles/4404012577299-Moving-Agents-Between-Organizations) to the appropriate organization after installation. 

### Optional Value

On line 52 you'll notice a value for `RMM`. This optional value allows  you to name the tool you're using to install the Huntress macOS agent, which may be helpful for our support team when troubleshooting. The value there is written to the `/tmp/HuntressInstaller.log` log file during installation and is not automatically sent to Huntress.

**NOTE**: Please do not modify anything below line 52. 