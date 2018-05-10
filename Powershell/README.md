### Deploying the Huntress Agent using Powershell

This Powershell script will install the Huntress Agent. When run, the script will automatically download and install the agent. The script does some basic error checking and logging. (It will check to see if the agent is already installed and also verfiy the installation completed.)

Your Huntress acccount key will need to be hard coded inside the script. You have the option to hard code the organization key or pass it as an argument to the script. [Click here for more details regarding the Account Key and Organization Key.](https://support.huntress.io/article/7-using-account-and-organization-keys)

Usage:
```
powershell -executionpolicy bypass -f ./InstallHuntress.powershellv1.ps1 [organization_key]
```
