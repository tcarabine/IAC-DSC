Configuration DomainController {
    
    param (
        [string]$NodeName,
        [Parameter(Mandatory)]             
        [pscredential]$safemodeAdministratorCred,             
        [Parameter(Mandatory)]            
        [pscredential]$domainCred        
        )
    
    Import-DscResource –ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xNetworking
    
    Node $AllNodes.Where{$_.Role -eq "DomainController"}.Nodename  {
        
        LocalConfigurationManager            
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyAndAutoCorrect'
            CertificateID = $Node.Thumbprint            
            RebootNodeIfNeeded = $true            
        }        

        xIPAddress IPAddress
        {
            IPAddress      = $Node.IPAddress
            InterfaceAlias = $Node.Ethernet
            SubnetMask     = 24
            AddressFamily  = "IPV4"
 
        }

        xDefaultGatewayAddress DefaultGateway
        {
            AddressFamily = 'IPv4'
            InterfaceAlias = $Node.Ethernet
            Address = $Node.DefaultGateway
            DependsOn = '[xIPAddress]IpAddress'

        }

        xDNSServerAddress DnsServerAddress
        {
            Address        = $Node.DNSIPAddress
            InterfaceAlias = $Node.Ethernet
            AddressFamily  = 'IPV4'
        }         
        
        WindowsFeature ADDSTools            
        {             
            Ensure = "Present"             
            Name = "RSAT-ADDS"             
        }

        File ADFiles            
        {            
            DestinationPath = 'C:\NTDS'            
            Type = 'Directory'            
            Ensure = 'Present'            
        }            
                    
        WindowsFeature ADDSInstall             
        {             
            Ensure = "Present"             
            Name = "AD-Domain-Services"
            IncludeAllSubFeature = $true
             
        }
        
        xADDomain FirstDS             
        {             
            DomainName = $Node.DomainName             
            DomainAdministratorCredential = $domainCred             
            SafemodeAdministratorPassword = $safemodeAdministratorCred            
            DatabasePath = 'C:\NTDS'            
            LogPath = 'C:\NTDS'            
            DependsOn = "[WindowsFeature]ADDSInstall","[File]ADFiles"            
        } 
                                                  
    }
}

$Params = @{
    Subject = 'CN=DC1'
    StoreLocation = 'LocalMachine'
    StoreName = 'My'
    EnhancedKeyUsage = 'Document Encryption'
    FriendlyName = 'SelfSigned'
}

New-SelfSignedCertificateEx @Params

$cert =
     Get-ChildItem Cert:\LocalMachine\my | 
     Where-Object {$_.FriendlyName -eq 'SelfSigned'}

if (-not (Test-Path c:\certs)){mkdir -Path c:\certs}
Export-Certificate -Cert $cert -FilePath C:\Certs\DC1.cer -Force
 

$ConfigData = @{             
    AllNodes = @(             
        @{             
            Nodename = 'DC1'          
            Role = "DomainController"
            DomainName = "globomantics.com"                         
            IPAddress = '192.168.2.10'
            DefaultGateway = '192.168.2.1'
            DNSIPAddress = '192.168.2.10','127.0.0.1'
            Ethernet = (Get-NetAdapter).Name
            Thumbprint = (Get-ChildItem Cert:\LocalMachine\my | Where-Object {$_.FriendlyName -eq 'SelfSigned'}).Thumbprint
            Certificatefile = 'c:\certs\DC1.cer'
            PsDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true     
        }
                      
    )             
} 

# Generate Configuration
DomainController -ConfigurationData $ConfigData `
-safemodeAdministratorCred (Get-Credential -UserName '(Password Only)' `
-Message "New Domain Safe Mode Administrator Password") `
-domainCred (Get-Credential -UserName globomantics\administrator `
-Message "New Domain Admin Credential") -OutputPath c:\dsc\NewDomain

 
Set-DscLocalConfigurationManager -Path c:\dsc\NewDomain -Verbose -Force
Start-DscConfiguration -wait -force -Verbose -Path c:\dsc\NewDomain\