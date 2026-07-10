## Deploying the Huntress Agent using PowerShell

This PowerShell script will install the Huntress Agent. The script will automatically download the installer from the Huntress servers and run it. The script is written to run on PowerShell versions 2 through 7, however some work may be required for older versions that may be missing TLS 1.2+, specific Microsoft updates, or other dependencies that are already built into modern versions of Windows. 

You have the option to hard code your Huntress account key, organization key, and tags (optional) in the script, or pass as arguments to the script. [Click here for more details regarding the Account Key and Organization Key.](https://support.huntress.io/hc/en-us/articles/4404012734227-Using-Account-Keys-Organization-Keys-and-Agent-Tags)

The script supports the following mutually exclusive command-line switches:
* `-reregister` - Force the agent to re-register (useful for clean install)
* `-reinstall` - Re-install the agent (useful for "repairing" an agent; this will replace all the files are restart the services)
* `-uninstall` - Forces the agent to uninstall itself; useful for corrupted installs

Usage:
```
powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 [-acctkey <account_key>] [-orgkey <organization_key>] [-tags <optional_tags_here>] [-reregister] [-reinstall] [-uninstall]
```


### Batch File Wrapper

We have also included a batch file, `InstallHuntress.bat`, to be used as a wrapper. This is useful if your RMM/SCCM application does not manage the PowerShell [`executionpolicy`.](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-3.0)

You'll need to edit the batch file, adding your Huntress account key. Then you can run the batch file as follows:

```
InstallHuntress.bat <organization_key> <optional tags>
```


See our documentation for more ways to deploy Huntress agents using this PowerShell script - https://support.huntress.io/hc/en-us/sections/22523543888915-Agent-Deployment-Windows
