### Deploying the Huntress Agent with N-Central

This policy will install the Huntress Agent. For full usage details please see https://support.huntress.io/article/46-deploying-huntress-with-solarwinds.

When run, the policy will automatically download and install the Huntress Agent. Before installing the agent, it will check to see if the agent is already installed. It will also verfiy the installation completed and log any errors.


The policy will pass the use specified [Account Key and Organization Key](https://support.huntress.io/article/7-using-account-and-organization-keys) to the installer via a simple Powershell script.
```
Start-Process $installer "/ACCT_KEY=`"$acctkey`" /ORG_KEY=`"$orgkey`" /S" -Wait
```
