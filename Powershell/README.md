### Deploying the Huntress Agent using Powershell

This Powershell script will install the Huntress Agent. The script will automatically download the installer from the Huntress servers and run it. The script does basic error checking and logging as well. (It will check to see if the agent is already installed and also verfiy the installation completed.)

Your Huntress acccount key will need to be hard coded inside the script. You have the option to hard code the organization key or pass it as an argument to the script. [Click here for more details regarding the Account Key and Organization Key.](https://support.huntress.io/article/7-using-account-and-organization-keys)

Usage:
```
powershell -executionpolicy bypass -f ./InstallHuntress.powershellv1.ps1 [organization_key]
```
