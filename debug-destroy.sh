#!/bin/bash

echo "Starting Debug Terraform Destroy (mirroring GitHub Actions delete pipeline)..."

# Navigate to terraform directory
cd terraform

# Create logs directory
mkdir -p ../.logs

# Step 1: Terraform Init
echo ""
echo "Step 1: Terraform Init"
echo "Initializing Terraform..."
TF_LOG=DEBUG TF_LOG_PATH=../.logs/debug-destroy-init.log terraform init -input=false

if [ $? -ne 0 ]; then
    echo "Terraform init failed!"
    exit 1
fi

# Step 2: Get ECS Cluster and Service Names
echo ""
echo "Step 2: Get ECS Cluster and Service Names"
CLUSTER_NAME=$(aws ecs list-clusters --region ap-southeast-1 --query 'clusterArns[0]' --output text | awk -F'/' '{print $NF}')
SERVICE_NAME=$(aws ecs list-services --cluster $CLUSTER_NAME --region ap-southeast-1 --query 'serviceArns[0]' --output text | awk -F'/' '{print $NF}')

if [ ! -z "$CLUSTER_NAME" ] && [ "$CLUSTER_NAME" != "None" ]; then
    echo "Found ECS Cluster: $CLUSTER_NAME"
    echo "Found ECS Service: $SERVICE_NAME"
    
    # Step 3: Scale ECS Service to Zero
    echo ""
    echo "Step 3: Scale ECS Service to Zero"
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --desired-count 0 \
        --region ap-southeast-1 2>&1 | tee ../.logs/debug-destroy-ecs-scale.log
    
    if [ $? -eq 0 ]; then
        echo "Scaled ECS service to 0 tasks"
    else
        echo "Warning: Failed to scale ECS service (might not exist)"
    fi
    
    # Step 4: Wait for Tasks to Stop
    echo ""
    echo "Step 4: Wait for Tasks to Stop"
    echo "Waiting for all tasks to stop..."
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region ap-southeast-1 2>&1 | tee -a ../.logs/debug-destroy-ecs-scale.log
    
    if [ $? -eq 0 ]; then
        echo "All tasks have stopped"
    else
        echo "Warning: Wait command failed (tasks might already be stopped)"
    fi
else
    echo "No ECS cluster found, skipping ECS cleanup"
fi

# Step 5: Delete Images from ECR
echo ""
echo "Step 5: Delete Images from ECR"
REPOSITORIES=$(aws ecr describe-repositories --region ap-southeast-1 --query 'repositories[*].repositoryName' --output text 2>&1)

if [ $? -eq 0 ] && [ ! -z "$REPOSITORIES" ]; then
    for REPO in $REPOSITORIES; do
        echo "Processing repository: $REPO"
        IMAGE_IDS=$(aws ecr list-images --repository-name $REPO --region ap-southeast-1 --query 'imageIds[*]' --output json)
        
        if [ "$IMAGE_IDS" != "[]" ] && [ ! -z "$IMAGE_IDS" ]; then
            aws ecr batch-delete-image \
                --repository-name $REPO \
                --image-ids "$IMAGE_IDS" \
                --region ap-southeast-1 2>&1 | tee ../.logs/debug-destroy-ecr-cleanup.log
            echo "Deleted images from $REPO"
        else
            echo "No images found in $REPO"
        fi
    done
else
    echo "No ECR repositories found, skipping ECR cleanup"
fi

# Step 6: Terraform Plan (Destroy)
echo ""
echo "Step 6: Terraform Plan (Destroy)"
echo "Running Terraform destroy plan..."
TF_LOG=DEBUG TF_LOG_PATH=../.logs/debug-destroy-plan.log terraform plan -destroy -out=tfdestroy 2>&1 | tee ../.logs/debug-destroy-plan-output.log

PLAN_EXIT_CODE=$?

# Step 7: Check for Lock Conflict
if grep -q "Error acquiring the state lock" ../.logs/debug-destroy-plan-output.log; then
    echo ""
    echo "Lock Conflict Detected"
    LOCK_ID=$(grep -oE 'ID:[[:space:]]*[0-9a-fA-F-]{36}' ../.logs/debug-destroy-plan-output.log | head -1 | grep -oE '[0-9a-fA-F-]{36}')
    
    if [ ! -z "$LOCK_ID" ]; then
        echo "Found stale lock ID: $LOCK_ID"
        read -p "Do you want to force unlock? (yes/no): " FORCE_UNLOCK
        
        if [ "$FORCE_UNLOCK" = "yes" ]; then
            echo "Force unlocking..."
            terraform force-unlock -force $LOCK_ID
            
            echo ""
            echo "Terraform Plan Retry"
            TF_LOG=DEBUG TF_LOG_PATH=../.logs/debug-destroy-plan-retry.log terraform plan -destroy -out=tfdestroy 2>&1 | tee ../.logs/debug-destroy-plan-retry-output.log
            PLAN_EXIT_CODE=$?
        fi
    fi
fi

if [ $PLAN_EXIT_CODE -ne 0 ]; then
    echo "Terraform destroy plan failed!"
    exit 1
fi

# Step 8: Apply Destroy Plan
echo ""
echo "Step 8: Terraform Destroy (Apply Destroy Plan)"
read -p "Do you want to apply the destroy plan? (yes/no): " APPLY_DESTROY

if [ "$APPLY_DESTROY" = "yes" ]; then
    echo "Applying Terraform destroy..."
    TF_LOG=DEBUG TF_LOG_PATH=../.logs/debug-destroy-apply.log terraform apply -input=false tfdestroy 2>&1 | tee ../.logs/debug-destroy-apply-output.log
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "Destroy Completed Successfully"
        echo "Terraform destroy completed successfully!"
    else
        echo ""
        echo "Destroy Failed"
        echo "Terraform destroy failed!"
        cd ..
        exit 1
    fi
    
    # Clean up plan file
    rm -f tfdestroy
else
    echo "Destroy plan not applied. Plan file saved at: terraform/tfdestroy"
fi

cd ..

echo ""
echo "Logs Summary"
echo "All logs are available in the .logs directory:"
echo "  - debug-destroy-init.log            : Terraform init logs"
echo "  - debug-destroy-ecs-scale.log       : ECS service scaling logs"
echo "  - debug-destroy-ecr-cleanup.log     : ECR image cleanup logs"
echo "  - debug-destroy-plan.log            : Terraform destroy plan (DEBUG)"
echo "  - debug-destroy-plan-output.log     : Terraform destroy plan output"
echo "  - debug-destroy-apply.log           : Terraform destroy apply (DEBUG)"
echo "  - debug-destroy-apply-output.log    : Terraform destroy apply output"
echo ""
echo "Debug destroy script completed!"
