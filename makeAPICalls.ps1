# region Functions
function Initialize {
	try {
		$IsWindows = ((Get-CimInstance -Class Win32_OperatingSystem).Caption -Match "Windows")	
	} catch {
		Write-Host "Error identifying OS: $_"
		$IsWindows = $false
	}
	$global:IsWindows = $IsWindows
	
	try {
		$global:osSlash = [IO.Path]::DirectorySeparatorChar
		$global:Config = $null
		$global:CurrPpath = Get-Location
		$global:ConfigFileName = 'config.json'
		$global:CacheFolderPath = ''
    $global:ConfigFileFullName = "$global:CurrPpath$global:osSlash$global:ConfigFileName"
		$global:Success = $true
		$global:AuthHeader = $null
		$global:Post = $null
	
	} catch {
		Write-Host "An error occurred: $_"
		$global:Success = $false
	}
}

function CheckCreateConfig {
# Checks if a file or folder exists, if it does not exist then it creates the full folder structure for folder, 
# for file it creates an empty file.
# params:	$entity -> 'file' or 'folder'
#					$path -> the full path to file or folder to be created
#					$name -> valid only for 'file', checks for file and creates the empty file if it does not exist.
	param([String]$entity, [String]$path, [String]$name = '')

	try {
		
		switch ($entity) {
					'file' 	{ 
						if (-not(Test-Path -Path ($path+$global:osSlash+$name))) {
							New-Item -ItemType File -Path $path -Name $name
							"File '{0}' has been created" -f ($path+$global:osSlash+$name)
						} 
					}
					'folder' 	{ 
						if (-not(Test-Path -Path $path)) {
							$null = New-Item -ItemType Directory -Path $path -Force
							"Folder '{0}' has been created" -f $path
						} 
					}
					default 	{ "Specify an entity to be created" }
		}
		$global:Success = $true
	} catch {
		Write-Host "An error occurred: $_"
		$global:Success = $false
	}
}

function LoadConfigs {
	CheckCreateConfig 'file' $global:CurrPpath $global:ConfigFileName
		
	try {
		$global:Config = Get-Content -Path $global:ConfigFileFullName | ConvertFrom-Json
    $global:CacheFolderPath = "$global:CurrPpath$global.osSlash"+$global:Config.cacheFolder
		
		$Host.UI.RawUI.WindowTitle = $global:Config.windowTitle
		$global:Success = $true
	} catch {
		Write-Host "An error occurred: $_"
		$global:Success = $false
	}
}

function GetToken {
	try {
			
		$authBody =  @{
				grant_type    = $global:Config.auth.grant_type
				client_id     = $global:Config.keyCloak.client_id
				client_secret = $global:Config.keyCloak.client_secret
		}

		$restSplat = @{
				Uri = $global:Config.keyCloak.token_endpoint
				Method = $global:Config.auth.method
				Body = $authBody
		}

		$connection = Invoke-WebRequest @restSplat
		$oToken = @($connection.Content) | ConvertFrom-Json

		$global:AuthHeader = @{
				'Authorization' = "$($oToken.token_type) $($oToken.access_token)"
				'accept' = $global:Config.auth.accept
				'Content-Type' = $global:Config.auth.content_type
		}

		$global:Success = $true
	} catch {
		Write-Host "An error occurred: $_.Exception.Message"
		$global:Success = $false
	}
}

function StageAPIRequest {
	param([String]$name, [String]$type = '')
	try {
		
		if($type) {
			$uri = $global:Config.entities.$name.$type.url 
			$formData = (("[{0}]" -f (($global:Config.entities.$name.$type.form_data) | ConvertTo-Json | Out-String)) | ConvertFrom-JSON) | ConvertTo-Json
		} else {
			$uri = $global:Config.entities.$name.url 
			$formData = (("[{0}]" -f (($global:Config.entities.$name.form_data) | ConvertTo-Json | Out-String)) | ConvertFrom-JSON) | ConvertTo-Json
		}
		if($formData -and $uri -and $global:Config.entities.method){
			$global:Post = @{
				Uri = $uri
				Method = $global:Config.entities.method
				Body = $formData
			}
			
			#$formData | ConvertTo-JSON
			#$post | ConvertTo-JSON
			#$post.Body #| ConvertTo-JSON
			
			$global:Success = $true
		} else {
			"Insufficient data"
			$global:Success = $false
		}
		
	} catch {
		"Error: {0} " -f $_
		$global:Success = $false
	}
}

function MakeAPICall {
	try {
		$response = Invoke-WebRequest @global:Post -Headers $global:AuthHeader
		$jsonObj = ConvertFrom-Json $([String]::new($response.Content))
		$jsonObj
		
		$global:Success = $true
	} catch {
		"Error: {0} " -f $_
		$global:Success = $false
	}
}
# endregion Functions

# region Main

Initialize
"Initialize success: {0}" -f $global:Success

if ($global:Success -eq $true) {
	LoadConfigs
	"LoadConfigs success: {0}" -f $global:Success
}

if ($global:Success -eq $true) {
	GetToken
	"GetToken success: {0}" -f $global:Success
}


if ($global:Success -eq $true) {
	$list = "{0}{1}{2}" -f $global:CurrPpath, $global:osSlash, $global:Config.listFileName
	foreach($item in Get-Content ($list)) {
		$a = $item -split " "
		$cbParam = ""
		for ($i = 0; $i -lt $a.Length; $i++) {
			if($i -eq 0) {
				$cbParam = ('"{0}"' -f $a[$i])
			} else {
				$cbParam = $cbParam + (' "{0}"' -f $a[$i])
			}
		}
		$fn = "StageAPIRequest"
		$cbParam 
		Invoke-Expression ("{0} {1}" -f $fn, $cbParam)
		"{0} success: {1}" -f $fn, $global:Success
		if ($global:Success -eq $true) {
			MakeAPICall
			"MakeAPICall success: {0}" -f $global:Success
			Start-Sleep -Seconds $global:Config.sleepSeconds
		}
	}
}

# endregion Main