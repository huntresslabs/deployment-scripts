### Deploying the Huntress Agent using Powershell

This Powershell script will install the Huntress Agent. When run, the script will automatically download and install the Huntress Agent. Before installing the agent, it will check to see if the agent is already installed. It will also verfiy the installation completed and log any errors.

Your Huntress acccount key will need to be hard coded in the script. You have the option to hard code the organization key or pass it as an argument to the script. [Click here for more details regarding the Account Key and Organization Key.](https://support.huntress.io/article/7-using-account-and-organization-keys)

Usage:
```
powershell -executionpolicy bypass -f ./InstallHuntress.powershellv1.ps1 [organization_key]
```
