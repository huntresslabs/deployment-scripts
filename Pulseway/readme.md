Huntress Deployment PowerShell v2 scripted wrapped within a function for deploying Huntress with Pulseway RMM.

Usage:

Install-Huntress [-acctkey <account_key>] [-orgkey <organization_key>] [-tags <optional_tags_here>] [-reregister] [-reinstall] [-uninstall] [-repair]

Examples:

 -acctkey 1234abc -orgkey hackerhunter

 -acctkey 1234abc -orgkey hackerhunter -tags "" -reinstall $false -reregister $false -uninstall $false -repair $false

]