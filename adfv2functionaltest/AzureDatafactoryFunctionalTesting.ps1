
Param(
    [Parameter(Mandatory = $True)]
   
    [string]$dataFactoryName,
    [string]$resourceGroupName,
    [string]$azureSubscription,
    [string]$applicationSecret,
    [string]$applicationID,
    [string]$tenantID,
    [string]$excludedPipelinesFilePath,
    [string]$functionalTestJsonFilePath
  
) 
  
    
#Silent Authentication using Service Principal Name (Application ID) - this need to be pulled using KeyVault during Release Process (Post Int Depolyments)
  
  
$securedPassword = ConvertTo-SecureString $applicationSecret -AsPlainText -Force
$systemCredentials = New-Object System.Management.Automation.PSCredential ($applicationID, $securedPassword)
  
  
Login-AzureRmAccount -ServicePrincipal -Tenant $tenantID -Credential $systemCredentials
  
  
$failedPipelines = New-Object System.Collections.ArrayList
  
  
#Selecting Factory for Functional Testing - can be Parameterized - this should be Int Environment 
Select-AzureRmSubscription $azureSubscription 
  
  
#Getting List of Pipelines in correspoinding Factory
$pipelines = Get-AzureRmDataFactoryV2Pipeline -ResourceGroupName $resourceGroupName -DataFactoryName $dataFactoryName
  
  
#Getting Excluded Pipelines - can be used for Component or Helper Pipelines which are invoked by other Pipelines
$excludedPipelines = Get-Content  $excludedPipelinesFilePath\PipelineExclusion.json | Out-String | ConvertFrom-Json
  
  
  
  
  
#Validating if Functional Test Exists (Test is parameters which we need to pass to Pipeline while calling it for functional test - test file name has to match with pipeline name with suffix as JSON)
  
foreach ($pipeline in $pipelines) {
  
    #checking Exception     
    if ($excludedPipelines.PipelineExclusion.Contains($pipeline.Name)) {
        Write-Host "Excluded Pipeline " $pipeline.Name -ForegroundColor Red
    }
  
    else {
  
        $parameterFile = $functionalTestJsonFilePath + "\" + $pipeline.Name + ".json"
        $pipelineName = $pipeline.Name 
      
      
        #Run test if JSON file exists
  
        if (Test-Path $parameterFile) {
  
            Write-Host "Running Test for "$pipeline.Name 
            Write-Host "Checking Test Timeout Value (Default is 30 Seconds)"
        
            #Reading content of parameter JSON file for getting value of Timeout Setting incase someone needs to orverride default behavior of 30 seconds
            $parameterFileJsonObject = Get-Content  $parameterFile | Out-String | ConvertFrom-Json
       
            #Setting Timeout - if its not stated in Paramter File then default it to 30 seconds otherwise consider value from Settings
             
            if ($parameterFileJsonObject.TestTimeout) {
                $testTimeout = $parameterFileJsonObject.TestTimeout
                Write-Host "Test Timeout (Seconds) :" $testTimeout
            }
            else {
                $testTimeout = 30
                Write-Host "Test Timeout (Seconds):" $testTimeout
            }
  
        
            $runId = Invoke-AzureRmDataFactoryV2Pipeline -DataFactoryName $dataFactoryName -ResourceGroupName $resourceGroupName -PipelineName $pipelineName  -ParameterFile $parameterFile
  
  
            #Chekcing Progress
          
            while ($True) {
                $run = Get-AzureRmDataFactoryV2PipelineRun -ResourceGroupName $resourceGroupName -DataFactoryName $DataFactoryName -PipelineRunId $runId
    
                Write-Host "***************************"
                $pipelineStartTime = [datetime] $run.RunStart.DateTime
                $currentTime = [DateTime]::UtcNow
                $pipelineDuration = $currentTime - $pipelineStartTime
                Write-Host "Time Elapsed(Minutes):" $pipelineDuration.Minutes
    
       
  
                if ( $pipelineDuration.Seconds -gt $testTimeout) {
                    Write-Host "Failed - Test for $pipelineName Status: Timeout $pipelineDuration" $run.Status -foregroundcolor "RED"
  
                    $failedPipelines.Add($pipelineName)
                    break
                }
  
                Write-Host "Running test for "   $pipelineName 
  
                if ($run) {
                    if ($run.Status -ne 'InProgress') {
                        if ($run.Status -eq 'Failed') {
                            $failedPipelines.Add($pipeline.Name)
                            Write-Host "Current Status of Pipeline "$run.Status 
                            break
                        }
                        Write-Host "Current Status of Pipeline "$run.Status 
                        break
                    }
   
                    $result = Get-AzureRmDataFactoryV2ActivityRun -DataFactoryName $dataFactoryName -ResourceGroupName $resourceGroupName -PipelineRunId $runId -RunStartedAfter (Get-Date).AddMinutes(-30) -RunStartedBefore (Get-Date).AddMinutes(30)
                    Write-Host "Current Status Of Pipeline:"$run.Status
                    Write-Host "Currently Running Activity:"$result.ActivityName
           
          
                }
  
                Start-Sleep -Seconds 5
            }
        }
  
        else {
            Write-Host "Failed - Test doesnt exist for "$pipeline.Name -foregroundcolor "Red"
            $failedPipelines.Add($pipeline.Name)
        }
    }
}
  
  
if ($failedPipelines.Count -gt 0) {
    Write-Host "Total Failures**********" $failedPipelines.Count 
    foreach ($failedPipeline in $failedPipelines) {
        Write-Host "Failed Pipelines " $failedPipeline
    }
    throw "Functional Test Failed"
}
  
  
