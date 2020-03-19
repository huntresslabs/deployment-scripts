This is just the PowerShell script for installing the Huntress Agent using AEM.

The component file includes the resource file which contains variables needed to run the script.

Please see the following document for usage details:
https://support.huntress.io/article/45-deploying-huntress-with-aem

This will install the Huntress Agent on your computers. The script will retrieve your Huntress account key from the DattoRMM account settings variable named HUNTRESS_ACCOUNT_KEY. The name of the site in DattoRMM will be used to associate the agent with an organization in the Huntress console. If the site name doesn't exist in Huntress it will be created automatically.
