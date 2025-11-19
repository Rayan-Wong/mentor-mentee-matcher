$ErrorActionPreference = "Stop"
$env:TF_CLI_ARGS = "-no-color"

Write-Host "Starting Debug Terraform Destroy (mirroring GitHub Actions delete pipeline)..."

# Save current directory and navigate to terraform directory
$originalDir = Get-Location
try {
    Set-Location (Join-Path $PSScriptRoot "terraform")

    # Create logs directory
    $logsDir = Join-Path $PSScriptRoot ".logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir | Out-Null
    }

    # Step 1: Terraform Init
    Write-Host ""
    Write-Host "Step 1: Terraform Init"
    Write-Host "Initializing Terraform..."
    $env:TF_LOG = "DEBUG"
    $env:TF_LOG_PATH = "../.logs/debug-destroy-init.log"
    terraform init -input=false
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform init failed!"
    }

    # Step 2: Get ECS Cluster and Service Names
    Write-Host ""
    Write-Host "Step 2: Get ECS Cluster and Service Names"
    
    try {
        $clusterArn = aws ecs list-clusters --region ap-southeast-1 --query 'clusterArns[0]' --output text 2>$null
        if ($clusterArn -and $clusterArn -ne "None") {
            $CLUSTER_NAME = $clusterArn.Split('/')[-1]
            $serviceArn = aws ecs list-services --cluster $CLUSTER_NAME --region ap-southeast-1 --query 'serviceArns[0]' --output text 2>$null
            $SERVICE_NAME = $serviceArn.Split('/')[-1]
            
            Write-Host "Found ECS Cluster: $CLUSTER_NAME"
            Write-Host "Found ECS Service: $SERVICE_NAME"
            
            # Step 3: Scale ECS Service to Zero
            Write-Host ""
            Write-Host "Step 3: Scale ECS Service to Zero"
            
            aws ecs update-service `
                --cluster $CLUSTER_NAME `
                --service $SERVICE_NAME `
                --desired-count 0 `
                --region ap-southeast-1 2>&1 | Tee-Object -FilePath "../.logs/debug-destroy-ecs-scale.log"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Scaled ECS service to 0 tasks"
            }
            else {
                Write-Host "Warning: Failed to scale ECS service (might not exist)"
            }
            
            # Step 4: Wait for Tasks to Stop
            Write-Host ""
            Write-Host "Step 4: Wait for Tasks to Stop"
            Write-Host "Waiting for all tasks to stop..."
            
            aws ecs wait services-stable `
                --cluster $CLUSTER_NAME `
                --services $SERVICE_NAME `
                --region ap-southeast-1 2>&1 | Tee-Object -FilePath "../.logs/debug-destroy-ecs-scale.log" -Append
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "All tasks have stopped"
            }
            else {
                Write-Host "Warning: Wait command failed (tasks might already be stopped)"
            }
        }
        else {
            Write-Host "No ECS cluster found, skipping ECS cleanup"
        }
    }
    catch {
        Write-Host "No ECS resources found or error accessing ECS, skipping cleanup"
    }

    # Step 5: Delete Images from ECR
    Write-Host ""
    Write-Host "Step 5: Delete Images from ECR"
    
    try {
        $repositories = aws ecr describe-repositories --region ap-southeast-1 --query 'repositories[*].repositoryName' --output text 2>$null
        
        if ($repositories -and $repositories -ne "") {
            foreach ($repo in $repositories.Split("`t")) {
                Write-Host "Processing repository: $repo"
                $imageIds = aws ecr list-images --repository-name $repo --region ap-southeast-1 --query 'imageIds[*]' --output json
                
                if ($imageIds -and $imageIds -ne "[]") {
                    aws ecr batch-delete-image `
                        --repository-name $repo `
                        --image-ids $imageIds `
                        --region ap-southeast-1 2>&1 | Tee-Object -FilePath "../.logs/debug-destroy-ecr-cleanup.log"
                    Write-Host "Deleted images from $repo"
                }
                else {
                    Write-Host "No images found in $repo"
                }
            }
        }
        else {
            Write-Host "No ECR repositories found, skipping ECR cleanup"
        }
    }
    catch {
        Write-Host "No ECR repositories found or error accessing ECR, skipping cleanup"
    }

    # Step 6: Terraform Plan (Destroy)
    Write-Host ""
    Write-Host "Step 6: Terraform Plan (Destroy)"
    Write-Host "Running Terraform destroy plan..."
    
    $env:TF_LOG = "DEBUG"
    $env:TF_LOG_PATH = "../.logs/debug-destroy-plan.log"
    terraform plan -destroy -out=tfdestroy 2>&1 | Tee-Object -FilePath "../.logs/debug-destroy-plan-output.log"
    $planExitCode = $LASTEXITCODE

    # Step 7: Check for Lock Conflict
    $planOutput = Get-Content "../.logs/debug-destroy-plan-output.log" -Raw
    if ($planOutput -match "Error acquiring the state lock") {
        Write-Host ""
        Write-Host "Lock Conflict Detected"
        
        if ($planOutput -match 'ID:\s*([0-9a-fA-F-]{36})') {
            $LOCK_ID = $Matches[1]
            Write-Host "Found stale lock ID: $LOCK_ID"
            
            $forceUnlock = Read-Host "Do you want to force unlock? (yes/no)"
            
            if ($forceUnlock -eq "yes") {
                Write-Host "Force unlocking..."
                terraform force-unlock -force $LOCK_ID
                
                Write-Host ""
                Write-Host "Terraform Plan Retry"
                $env:TF_LOG_PATH = "../.logs/debug-destroy-plan-retry.log"
                terraform plan -destroy -out=tfdestroy 2>&1 | Tee-Object -FilePath "../.logs/debug-destroy-plan-retry-output.log"
                $planExitCode = $LASTEXITCODE
            }
        }
    }

    if ($planExitCode -ne 0) {
        throw "Terraform destroy plan failed!"
    }

    # Step 8: Apply Destroy Plan
    Write-Host ""
    Write-Host "Step 8: Terraform Destroy (Apply Destroy Plan)"
    
    $applyDestroy = Read-Host "Do you want to apply the destroy plan? (yes/no)"
    
    if ($applyDestroy -eq "yes") {
        Write-Host "Applying Terraform destroy..."
        $env:TF_LOG_PATH = "../.logs/debug-destroy-apply.log"
        terraform apply -input=false tfdestroy 2>&1 | Tee-Object -FilePath "../.logs/debug-destroy-apply-output.log"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "Destroy Completed Successfully"
            Write-Host "Terraform destroy completed successfully!"
        }
        else {
            Write-Host ""
            Write-Host "Destroy Failed"
            throw "Terraform destroy failed!"
        }
        
        # Clean up plan file
        Remove-Item -Path "tfdestroy" -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "Destroy plan not applied. Plan file saved at: terraform/tfdestroy"
    }

    Write-Host ""
    Write-Host "Logs Summary"
    Write-Host "All logs are available in the .logs directory:"
    Write-Host "  - debug-destroy-init.log            : Terraform init logs"
    Write-Host "  - debug-destroy-ecs-scale.log       : ECS service scaling logs"
    Write-Host "  - debug-destroy-ecr-cleanup.log     : ECR image cleanup logs"
    Write-Host "  - debug-destroy-plan.log            : Terraform destroy plan (DEBUG)"
    Write-Host "  - debug-destroy-plan-output.log     : Terraform destroy plan output"
    Write-Host "  - debug-destroy-apply.log           : Terraform destroy apply (DEBUG)"
    Write-Host "  - debug-destroy-apply-output.log    : Terraform destroy apply output"
    Write-Host ""
    Write-Host "Debug destroy script completed!"
}
catch {
    Write-Host "Error: $_"
    Set-Location $originalDir
    exit 1
}
finally {
    Set-Location $originalDir
}
